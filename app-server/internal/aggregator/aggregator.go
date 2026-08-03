package aggregator

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
	"github.com/funwithactivity/funwithactivity/app-server/internal/providers"
	"github.com/funwithactivity/funwithactivity/app-server/internal/ranking"
)

// ProviderStatus reports what each provider did on this request. It is what
// makes partial failure visible in the UI instead of silent.
type ProviderStatus struct {
	Name      string
	OK        bool
	Skipped   bool // Requires() was not satisfied — we did not call it
	Error     string
	Count     int
	LatencyMs int64
}

type Result struct {
	Recommendations []domain.Recommendation
	Statuses        []ProviderStatus
}

type Aggregator struct {
	providers          []providers.Provider
	perProviderTimeout time.Duration
	cache              Cache
	ranker             ranking.Ranker
	deduper            ranking.Deduper
}

// defaultPerProviderTimeout is used when the caller supplies a zero (or
// negative) timeout. Without this guard, context.WithTimeout(ctx, 0) is
// already expired at creation, so every provider call would fail instantly
// and silently — a total outage that returns a 200 with zero recommendations
// and no error, indistinguishable at a glance from "no providers matched".
const defaultPerProviderTimeout = 2 * time.Second

func New(p []providers.Provider, perProviderTimeout time.Duration, cache Cache, r ranking.Ranker) *Aggregator {
	if cache == nil {
		cache = NoopCache{}
	}
	if r == nil {
		r = ranking.NewWeightedNormalized(nil)
	}
	if perProviderTimeout <= 0 {
		perProviderTimeout = defaultPerProviderTimeout
	}
	return &Aggregator{
		providers:          p,
		perProviderTimeout: perProviderTimeout,
		cache:              cache,
		ranker:             r,
		// Not a constructor parameter: exact-title dedupe is a correctness
		// fix (live vendor responses repeat titles both within one
		// provider's response and across providers), not a policy knob
		// callers should need to swap like the Ranker.
		deduper: ranking.NewExactTitleDeduper(),
	}
}

type providerResult struct {
	filled bool // distinguishes "never written" from a real zero-value status
	status ProviderStatus
	recs   []domain.Recommendation
}

// Aggregate fans out to every provider whose requirements the supplied
// measurements satisfy, in parallel, each with its own deadline. Failed
// providers are recorded and excluded; a failing provider must never fail
// the whole request. The returned Result is read-only: on a cache hit it
// aliases the cached entry, so callers must not mutate it in place.
//
// Deliberately sync.WaitGroup rather than errgroup: errgroup short-circuits
// on the first error, which is exactly the isolation we need to preserve.
func (a *Aggregator) Aggregate(ctx context.Context, m domain.Measurements) (Result, error) {
	key := cacheKey(m)
	if cached, ok := a.cache.Get(ctx, key); ok {
		return cached, nil
	}

	results := make([]providerResult, len(a.providers))
	var wg sync.WaitGroup

	for i, p := range a.providers {
		if !p.Requires().SatisfiedBy(m) {
			results[i] = providerResult{filled: true, status: ProviderStatus{
				Name:    p.Name(),
				Skipped: true,
				Error:   "required measurements not supplied",
			}}
			continue
		}

		wg.Add(1)
		go func(i int, p providers.Provider) {
			// defer order is load-bearing: recover must run before Done.
			// Deferred calls execute LIFO, so registering wg.Done() first
			// and the recover-and-write defer second means, on panic,
			// results[i] is written before wg.Wait() can return — otherwise
			// the main goroutine could read results[i] concurrently with
			// this goroutine's recovery write, a genuine data race.
			defer wg.Done()
			defer func() {
				if r := recover(); r != nil {
					results[i] = providerResult{filled: true, status: ProviderStatus{
						Name: p.Name(), OK: false, Error: fmt.Sprintf("panic: %v", r),
					}}
				}
			}()

			pCtx, cancel := context.WithTimeout(ctx, a.perProviderTimeout)
			defer cancel()

			start := time.Now()
			recs, err := p.Fetch(pCtx, m)
			latency := time.Since(start).Milliseconds()

			st := ProviderStatus{Name: p.Name(), OK: err == nil, Count: len(recs), LatencyMs: latency}
			if err != nil {
				st.Error = err.Error()
			}

			// No PHI in logs: provider name, counts and timings only.
			slog.InfoContext(ctx, "provider fetch",
				"provider", p.Name(), "ok", err == nil,
				"count", len(recs), "latency_ms", latency)

			results[i] = providerResult{filled: true, status: st, recs: recs}
		}(i, p)
	}
	wg.Wait()

	merged := make([]domain.Recommendation, 0)
	statuses := make([]ProviderStatus, 0, len(results))
	complete := true
	for _, r := range results {
		if !r.filled {
			continue
		}
		statuses = append(statuses, r.status)
		if r.status.OK {
			merged = append(merged, r.recs...)
		} else if !r.status.Skipped {
			complete = false
		}
	}

	// Dedupe before ranking: live vendor responses contain exact-title
	// repeats both within a single provider's response and across the two
	// providers. Deduping the merged set (not each provider's slice
	// separately) is what collapses the cross-provider case.
	deduped := a.deduper.Dedupe(merged)
	out := Result{Recommendations: a.ranker.Rank(deduped), Statuses: statuses}

	// If the caller's context is already done (client disconnected, gateway
	// timeout), every provider likely returned ctx.Err() and out is empty or
	// degraded. Returning it as a normal, cacheable success would poison the
	// cache key for every other user sharing these measurements — they would
	// get this caller's empty result from cache instead of a fresh attempt.
	// Surface the cancellation instead, distinct from a provider failure
	// (which must still return nil), and skip the cache write entirely.
	if ctx.Err() != nil {
		return out, ctx.Err()
	}

	// Only cache a complete result: if any provider failed (not merely
	// skipped by requirement routing), caching it would make that
	// provider's later recovery invisible — the next call would be served
	// the stale degraded Result from cache and never re-call the provider.
	if complete {
		a.cache.Set(ctx, key, out)
	}
	return out, nil
}

// cacheKey is derived from the inputs that change the answer. Birth date is
// bucketed to the day: finer precision would make the key unique per user
// per second and defeat caching entirely.
func cacheKey(m domain.Measurements) string {
	dob := "none"
	if m.BirthDate != nil {
		dob = m.BirthDate.UTC().Format("2006-01-02")
	}
	return fmt.Sprintf("recs:%.1f:%.1f:%s", m.HeightCm, m.WeightKg, dob)
}
