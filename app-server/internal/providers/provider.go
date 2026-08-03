package providers

import (
	"context"
	"log/slog"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
)

// Provider fetches recommendations from one upstream source. Implementations
// MUST honour ctx cancellation and return promptly on timeout.
//
// Adding a provider is: implement this interface in a new file, register it
// in registry.go, add a table test. Nothing in aggregator/ changes.
type Provider interface {
	Name() string
	// Requires declares which measurement fields this provider needs. The
	// aggregator skips providers whose requirements are unmet rather than
	// calling them with placeholder data.
	Requires() domain.FieldSet
	Fetch(ctx context.Context, m domain.Measurements) ([]domain.Recommendation, error)
}

// clampNormScore forces a normalised score into [0, 1] at the adapter
// boundary. This vendor pool is known to return non-deterministic data and
// misleading error codes, so a single out-of-range value (confidence > 1,
// priority > 1000, or either negative) must never be allowed to dominate or
// invert the merged ranking. Clamping is logged at WARN — silently
// correcting vendor drift would hide it — but the request still succeeds
// with a corrected score rather than failing outright.
func clampNormScore(providerName string, raw, normScore float64) float64 {
	clamped := normScore
	if clamped < 0 {
		clamped = 0
	} else if clamped > 1 {
		clamped = 1
	}
	if clamped != normScore {
		slog.Warn("provider returned an out-of-range score; clamped",
			"provider", providerName,
			"raw_value", raw,
			"computed_norm_score", normScore,
			"clamped_norm_score", clamped,
		)
	}
	return clamped
}
