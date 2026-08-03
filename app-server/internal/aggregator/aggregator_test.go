package aggregator

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
	"github.com/funwithactivity/funwithactivity/app-server/internal/providers"
	"github.com/funwithactivity/funwithactivity/app-server/internal/ranking"
	"github.com/stretchr/testify/require"
)

type fakeProvider struct {
	name     string
	requires domain.FieldSet
	recs     []domain.Recommendation
	err      error
	delay    time.Duration
}

func (f *fakeProvider) Name() string              { return f.name }
func (f *fakeProvider) Requires() domain.FieldSet { return f.requires }
func (f *fakeProvider) BaseURL() string           { return "https://" + f.name + ".example.test" }
func (f *fakeProvider) Fetch(ctx context.Context, _ domain.Measurements) ([]domain.Recommendation, error) {
	if f.delay > 0 {
		select {
		case <-time.After(f.delay):
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	if f.err != nil {
		return nil, f.err
	}
	return f.recs, nil
}

func metric() domain.Measurements {
	return domain.Measurements{HeightCm: 184, WeightKg: 84}
}

func withDOB() domain.Measurements {
	dob := time.Unix(1615876858, 0)
	m := metric()
	m.BirthDate = &dob
	return m
}

func newAgg(ps []providers.Provider, timeout time.Duration) *Aggregator {
	return New(ps, timeout, nil, ranking.NewWeightedNormalized(nil))
}

func TestAggregate_MergesAndRanksAcrossProviders(t *testing.T) {
	p1 := &fakeProvider{name: "s1", requires: domain.Of(domain.FieldHeight),
		recs: []domain.Recommendation{{Title: "Walk more", Source: "s1", NormScore: 0.4}}}
	p2 := &fakeProvider{name: "s2", requires: domain.Of(domain.FieldHeight),
		recs: []domain.Recommendation{{Title: "Workouts", Source: "s2", NormScore: 0.75}}}

	got, err := newAgg([]providers.Provider{p1, p2}, time.Second).Aggregate(context.Background(), metric())

	require.NoError(t, err)
	require.Len(t, got.Recommendations, 2)
	require.Equal(t, "Workouts", got.Recommendations[0].Title, "higher score ranks first")
}

func TestAggregate_IsolatesFailingProvider(t *testing.T) {
	bad := &fakeProvider{name: "s1", requires: domain.Of(domain.FieldHeight),
		err: errors.New("upstream broken")}
	good := &fakeProvider{name: "s2", requires: domain.Of(domain.FieldHeight),
		recs: []domain.Recommendation{{Title: "Workouts", Source: "s2", NormScore: 0.75}}}

	got, err := newAgg([]providers.Provider{bad, good}, time.Second).Aggregate(context.Background(), metric())

	require.NoError(t, err, "one failing provider must never fail the request")
	require.Len(t, got.Recommendations, 1)
	require.Len(t, got.Statuses, 2)

	byName := statusesByName(got.Statuses)
	require.False(t, byName["s1"].OK)
	require.Contains(t, byName["s1"].Error, "upstream broken")
	require.True(t, byName["s2"].OK)
	require.Equal(t, 1, byName["s2"].Count)
}

func TestAggregate_SkipsProviderWithUnmetRequirements(t *testing.T) {
	calls := 0
	needsDOB := &countingProvider{calls: &calls, inner: &fakeProvider{name: "s2",
		requires: domain.Of(domain.FieldHeight, domain.FieldWeight, domain.FieldBirthDate),
		recs:     []domain.Recommendation{{Title: "Workouts", Source: "s2", NormScore: 0.75}}}}
	noDOB := &fakeProvider{name: "s1",
		requires: domain.Of(domain.FieldHeight, domain.FieldWeight),
		recs:     []domain.Recommendation{{Title: "Walk more", Source: "s1", NormScore: 0.4}}}

	got, err := newAgg([]providers.Provider{needsDOB, noDOB}, time.Second).
		Aggregate(context.Background(), metric()) // no birth date

	require.NoError(t, err)
	require.Len(t, got.Recommendations, 1)
	require.Equal(t, "Walk more", got.Recommendations[0].Title)

	byName := statusesByName(got.Statuses)
	require.True(t, byName["s2"].Skipped, "provider requiring DOB must be skipped, not called")
	require.False(t, byName["s2"].OK)
	require.False(t, byName["s1"].Skipped)
	require.Equal(t, 0, calls, "skipped provider must never be called")
}

func TestAggregate_RunsSkippedProviderWhenRequirementMet(t *testing.T) {
	needsDOB := &fakeProvider{name: "s2",
		requires: domain.Of(domain.FieldBirthDate),
		recs:     []domain.Recommendation{{Title: "Workouts", Source: "s2", NormScore: 0.75}}}

	got, err := newAgg([]providers.Provider{needsDOB}, time.Second).
		Aggregate(context.Background(), withDOB())

	require.NoError(t, err)
	require.Len(t, got.Recommendations, 1)
	require.False(t, statusesByName(got.Statuses)["s2"].Skipped)
}

func TestAggregate_SlowProviderDoesNotBlockFastOne(t *testing.T) {
	slow := &fakeProvider{name: "slow", requires: domain.Of(domain.FieldHeight),
		recs:  []domain.Recommendation{{Title: "late", Source: "slow", NormScore: 0.9}},
		delay: 300 * time.Millisecond}
	fast := &fakeProvider{name: "fast", requires: domain.Of(domain.FieldHeight),
		recs: []domain.Recommendation{{Title: "quick", Source: "fast", NormScore: 0.5}}}

	start := time.Now()
	got, err := newAgg([]providers.Provider{slow, fast}, 50*time.Millisecond).
		Aggregate(context.Background(), metric())
	elapsed := time.Since(start)

	require.NoError(t, err)
	require.Less(t, elapsed, 200*time.Millisecond)
	require.Len(t, got.Recommendations, 1)
	require.Equal(t, "quick", got.Recommendations[0].Title)
}

func TestAggregate_EmptyProviderList(t *testing.T) {
	got, err := newAgg(nil, time.Second).Aggregate(context.Background(), metric())
	require.NoError(t, err)
	require.Empty(t, got.Recommendations)
	require.Empty(t, got.Statuses)
}

func TestAggregate_UsesCacheWhenWarm(t *testing.T) {
	calls := 0
	p := &fakeProvider{name: "s1", requires: domain.Of(domain.FieldHeight),
		recs: []domain.Recommendation{{Title: "Walk more", Source: "s1", NormScore: 0.4}}}

	counting := &countingProvider{inner: p, calls: &calls}
	cache := &memCache{data: map[string]Result{}}
	agg := New([]providers.Provider{counting}, time.Second, cache, ranking.NewWeightedNormalized(nil))

	_, err := agg.Aggregate(context.Background(), metric())
	require.NoError(t, err)
	_, err = agg.Aggregate(context.Background(), metric())
	require.NoError(t, err)

	require.Equal(t, 1, calls, "second identical request must be served from cache")
}

func TestAggregate_DoesNotCacheDegradedResult(t *testing.T) {
	p := &recoveringProvider{name: "s1", requires: domain.Of(domain.FieldHeight),
		failFor: 1,
		recs:    []domain.Recommendation{{Title: "Walk more", Source: "s1", NormScore: 0.4}}}
	cache := &memCache{data: map[string]Result{}}
	agg := New([]providers.Provider{p}, time.Second, cache, ranking.NewWeightedNormalized(nil))

	got1, err := agg.Aggregate(context.Background(), metric())
	require.NoError(t, err)
	require.Empty(t, got1.Recommendations, "first call's only provider fails")
	require.Empty(t, cache.data, "a degraded (partially failed) result must not be cached")

	got2, err := agg.Aggregate(context.Background(), metric())
	require.NoError(t, err)
	require.Len(t, got2.Recommendations, 1,
		"provider recovered; second call must re-fetch, not serve the stale failure from cache")
	require.Equal(t, 2, p.calls, "provider must be called again on the second request")
}

func TestAggregate_CancelledContextIsNotCached(t *testing.T) {
	p := &fakeProvider{name: "s1", requires: domain.Of(domain.FieldHeight),
		delay: 10 * time.Millisecond,
		recs:  []domain.Recommendation{{Title: "Walk more", Source: "s1", NormScore: 0.4}}}
	cache := &memCache{data: map[string]Result{}}
	agg := New([]providers.Provider{p}, time.Second, cache, ranking.NewWeightedNormalized(nil))

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // caller already gone before Aggregate even starts the fan-out

	got, err := agg.Aggregate(ctx, metric())

	require.Error(t, err, "a cancelled caller context must surface as an error, distinct from provider failure")
	require.Empty(t, got.Recommendations)
	require.Empty(t, cache.data,
		"an empty result caused by caller cancellation must not be cached for other callers sharing this key")
}

func TestAggregate_StubProvidersMergeAndRankInterleaved(t *testing.T) {
	stubs := []providers.Provider{providers.NewService1Stub(), providers.NewService2Stub()}

	got, err := newAgg(stubs, time.Second).Aggregate(context.Background(), withDOB())

	require.NoError(t, err)
	require.Len(t, got.Recommendations, 6)

	wantTitles := []string{
		"Drink more water",                // service1-stub, 0.9
		"Aim for 7–8 hours of sleep",      // service2-stub, 0.9 (tie, later in fan-out order)
		"Have more workouts per day",      // service2-stub, 0.75
		"Improve your sleep schedule",     // service1-stub, 0.65
		"Walk more",                       // service1-stub, 0.4
		"Add 20 push-ups to your morning", // service2-stub, 0.4 (tie, later in fan-out order)
	}
	gotTitles := make([]string, len(got.Recommendations))
	for i, r := range got.Recommendations {
		gotTitles[i] = r.Title
	}
	require.Equal(t, wantTitles, gotTitles,
		"merged output must interleave both providers' recommendations, not block them by source")

	// Both providers must actually be represented in the top results, not
	// just merged then re-sorted back into per-provider blocks.
	require.Equal(t, "service1-stub", got.Recommendations[0].Source)
	require.Equal(t, "service2-stub", got.Recommendations[1].Source)
}

func TestAggregate_StatusCarriesProviderBaseURL(t *testing.T) {
	ok := &fakeProvider{name: "s1", requires: domain.Of(domain.FieldHeight),
		recs: []domain.Recommendation{{Title: "Walk more", Source: "s1", NormScore: 0.4}}}
	skipped := &fakeProvider{name: "s2",
		requires: domain.Of(domain.FieldHeight, domain.FieldWeight, domain.FieldBirthDate)}

	got, err := newAgg([]providers.Provider{ok, skipped}, time.Second).Aggregate(context.Background(), metric())
	require.NoError(t, err)

	byName := statusesByName(got.Statuses)
	require.Equal(t, "https://s1.example.test", byName["s1"].BaseURL,
		"a called provider's status must carry its configured endpoint")
	require.Equal(t, "https://s2.example.test", byName["s2"].BaseURL,
		"a skipped provider's status must still carry its configured endpoint")
}

func TestAggregate_RecoversFromPanickingProvider(t *testing.T) {
	boom := &panicProvider{name: "boom", requires: domain.Of(domain.FieldHeight)}
	good := &fakeProvider{name: "s2", requires: domain.Of(domain.FieldHeight),
		recs: []domain.Recommendation{{Title: "Workouts", Source: "s2", NormScore: 0.75}}}

	got, err := newAgg([]providers.Provider{boom, good}, time.Second).Aggregate(context.Background(), metric())

	require.NoError(t, err, "a panicking provider must never fail the whole request")
	require.Len(t, got.Recommendations, 1)
	require.Equal(t, "Workouts", got.Recommendations[0].Title)

	byName := statusesByName(got.Statuses)
	require.False(t, byName["boom"].OK)
	require.Contains(t, byName["boom"].Error, "panic")
	require.True(t, byName["s2"].OK)
}

type recoveringProvider struct {
	name     string
	requires domain.FieldSet
	calls    int
	failFor  int // Fetch fails for the first failFor calls, then succeeds
	recs     []domain.Recommendation
}

func (p *recoveringProvider) Name() string              { return p.name }
func (p *recoveringProvider) Requires() domain.FieldSet { return p.requires }
func (p *recoveringProvider) BaseURL() string           { return "https://" + p.name + ".example.test" }
func (p *recoveringProvider) Fetch(context.Context, domain.Measurements) ([]domain.Recommendation, error) {
	p.calls++
	if p.calls <= p.failFor {
		return nil, errors.New("still down")
	}
	return p.recs, nil
}

type panicProvider struct {
	name     string
	requires domain.FieldSet
}

func (p *panicProvider) Name() string              { return p.name }
func (p *panicProvider) Requires() domain.FieldSet { return p.requires }
func (p *panicProvider) BaseURL() string           { return "https://" + p.name + ".example.test" }
func (p *panicProvider) Fetch(context.Context, domain.Measurements) ([]domain.Recommendation, error) {
	panic("boom")
}

type countingProvider struct {
	inner providers.Provider
	calls *int
}

func (c *countingProvider) Name() string              { return c.inner.Name() }
func (c *countingProvider) Requires() domain.FieldSet { return c.inner.Requires() }
func (c *countingProvider) BaseURL() string           { return c.inner.BaseURL() }
func (c *countingProvider) Fetch(ctx context.Context, m domain.Measurements) ([]domain.Recommendation, error) {
	*c.calls++
	return c.inner.Fetch(ctx, m)
}

type memCache struct{ data map[string]Result }

func (m *memCache) Get(_ context.Context, k string) (Result, bool) { v, ok := m.data[k]; return v, ok }
func (m *memCache) Set(_ context.Context, k string, v Result)      { m.data[k] = v }

func statusesByName(ss []ProviderStatus) map[string]ProviderStatus {
	out := make(map[string]ProviderStatus, len(ss))
	for _, s := range ss {
		out[s.Name] = s
	}
	return out
}
