// Package ranking merges recommendations from providers whose scoring scales
// are not the same quantity.
//
// Service 1 reports `confidence` (how sure its model is). Service 2 reports
// `priority` (how important its editors think the tip is). Projecting both
// onto one axis is a judgment call, not an equivalence — the per-provider
// weights are where that judgment lives, and the production answer is to
// calibrate them against outcome data (did the user act on the tip?) rather
// than to hardcode a constant.
package ranking

import (
	"sort"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
)

// Ranker is the seam the customer is most likely to ask us to change during
// live coding: "rank by recency", "weight provider 2 higher", "add a third
// provider". Swapping the implementation touches nothing else.
type Ranker interface {
	Rank([]domain.Recommendation) []domain.Recommendation
}

// WeightedNormalizedRanker multiplies each already-normalised 0..1 score by
// a per-provider trust weight and sorts descending.
type WeightedNormalizedRanker struct {
	Weights map[string]float64
}

func NewWeightedNormalized(weights map[string]float64) WeightedNormalizedRanker {
	return WeightedNormalizedRanker{Weights: weights}
}

func (r WeightedNormalizedRanker) Rank(in []domain.Recommendation) []domain.Recommendation {
	out := make([]domain.Recommendation, len(in))
	copy(out, in)

	for i := range out {
		// Weight is keyed on PrimarySource, not Source: after Deduper
		// merges cross-provider duplicates, Source becomes a joined
		// display string (e.g. "service1, service2") that matches no
		// configured weight key. PrimarySource carries the winning
		// record's own single provider — see the seam note on
		// domain.Recommendation — so weighting stays exactly what it was
		// before merging existed. Falling back to Source when
		// PrimarySource is empty keeps un-deduped callers (and older
		// records built without it) behaving exactly as before.
		source := out[i].PrimarySource
		if source == "" {
			source = out[i].Source
		}
		out[i].FinalScore = out[i].NormScore * r.weightFor(source)
	}

	// Stable so equal scores preserve provider fan-out order, which keeps
	// the demo's output deterministic between runs.
	sort.SliceStable(out, func(a, b int) bool {
		return out[a].FinalScore > out[b].FinalScore
	})
	return out
}

// weightFor defaults to 1.0 so a newly registered provider ranks sensibly
// before anyone has tuned its weight.
func (r WeightedNormalizedRanker) weightFor(source string) float64 {
	if w, ok := r.Weights[source]; ok {
		return w
	}
	return 1.0
}
