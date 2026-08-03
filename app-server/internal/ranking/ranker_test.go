package ranking

import (
	"testing"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
	"github.com/stretchr/testify/require"
)

func rec(title, source string, norm float64) domain.Recommendation {
	return domain.Recommendation{Title: title, Source: source, NormScore: norm}
}

func TestRank_SortsByFinalScoreDescending(t *testing.T) {
	in := []domain.Recommendation{
		rec("low", "service1", 0.2),
		rec("high", "service1", 0.9),
		rec("mid", "service1", 0.5),
	}
	got := NewWeightedNormalized(nil).Rank(in)
	require.Equal(t, []string{"high", "mid", "low"},
		[]string{got[0].Title, got[1].Title, got[2].Title})
}

func TestRank_AppliesPerProviderWeight(t *testing.T) {
	in := []domain.Recommendation{
		rec("from-trusted", "service2", 0.5),
		rec("from-untrusted", "service1", 0.8),
	}
	got := NewWeightedNormalized(map[string]float64{
		"service1": 0.5,
		"service2": 1.0,
	}).Rank(in)

	require.Equal(t, "from-trusted", got[0].Title,
		"0.5*1.0 must outrank 0.8*0.5")
	require.InDelta(t, 0.5, got[0].FinalScore, 0.0001)
	require.InDelta(t, 0.4, got[1].FinalScore, 0.0001)
}

func TestRank_DefaultsUnknownProviderWeightToOne(t *testing.T) {
	in := []domain.Recommendation{rec("x", "service3", 0.7)}
	got := NewWeightedNormalized(map[string]float64{"service1": 0.5}).Rank(in)
	require.InDelta(t, 0.7, got[0].FinalScore, 0.0001,
		"a newly added provider must rank sensibly before its weight is tuned")
}

func TestRank_IsStableForEqualScores(t *testing.T) {
	in := []domain.Recommendation{
		rec("first", "service1", 0.5),
		rec("second", "service1", 0.5),
	}
	got := NewWeightedNormalized(nil).Rank(in)
	require.Equal(t, "first", got[0].Title)
	require.Equal(t, "second", got[1].Title)
}

func TestRank_EmptyInput(t *testing.T) {
	require.Empty(t, NewWeightedNormalized(nil).Rank(nil))
}

// TestDedupeThenRank_CrossProviderMergePreservesWinnersWeight is a
// regression guard on the Dedupe/Rank seam: ExactTitleDeduper.Dedupe joins
// Source into a display string (e.g. "service1, service2") for a
// cross-provider duplicate. Rank must still resolve the per-provider weight
// from the record that actually won dedupe (via PrimarySource), exactly as
// it would have before Source ever carried more than one provider — not
// silently default every merged record to weight 1.0 because the joined
// Source matches no configured key.
func TestDedupeThenRank_CrossProviderMergePreservesWinnersWeight(t *testing.T) {
	weights := map[string]float64{"service1": 1.0, "service2": 0.3}

	// service1 wins on score; service2 is the duplicate that gets merged in.
	winner := rec("Don't eat carbs!", "service1", 0.96)
	loser := rec("Don't eat carbs!", "service2", 0.33)

	deduped := NewExactTitleDeduper().Dedupe([]domain.Recommendation{winner, loser})
	require.Len(t, deduped, 1)
	require.Equal(t, "service1, service2", deduped[0].Source,
		"Source stays the joined display string")
	require.Equal(t, "service1", deduped[0].PrimarySource,
		"PrimarySource is the winner's own, pre-merge provider")

	ranked := NewWeightedNormalized(weights).Rank(deduped)
	require.Len(t, ranked, 1)
	require.InDelta(t, 0.96*1.0, ranked[0].FinalScore, 0.0001,
		"merged record must be weighted as service1 (the winner), matching what it would have "+
			"scored before Source ever carried more than one provider — not defaulted to weight 1.0 "+
			"because the joined Source matches no configured key")

	// Same check the other way round: a service2 win (lower weight, 0.3)
	// must not be masked by service1 also being listed in the merged Source.
	winner2 := rec("Walk more", "service2", 0.9)
	loser2 := rec("Walk more", "service1", 0.2)
	deduped2 := NewExactTitleDeduper().Dedupe([]domain.Recommendation{winner2, loser2})
	ranked2 := NewWeightedNormalized(weights).Rank(deduped2)
	require.Len(t, ranked2, 1)
	require.InDelta(t, 0.9*0.3, ranked2[0].FinalScore, 0.0001,
		"merged record won by service2 must be weighted 0.3, not defaulted to 1.0")
}
