package ranking

import (
	"testing"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
	"github.com/stretchr/testify/require"
)

func TestDedupe_CollapsesWithinSingleProviderRepeats(t *testing.T) {
	in := []domain.Recommendation{
		rec("Don't eat carbs!", "service1", 0.35),
		rec("Don't eat carbs!", "service1", 0.60),
		rec("Don't eat carbs!", "service1", 0.12),
		rec("Drink more still water", "service1", 0.30),
		rec("Drink more still water", "service1", 0.90),
	}

	got := NewExactTitleDeduper().Dedupe(in)

	require.Len(t, got, 2)
	byTitle := indexByTitle(got)
	require.InDelta(t, 0.60, byTitle["Don't eat carbs!"].NormScore, 0.0001,
		"highest-scoring instance among the repeats must survive")
	require.InDelta(t, 0.90, byTitle["Drink more still water"].NormScore, 0.0001)
	require.Equal(t, "service1", byTitle["Don't eat carbs!"].Source,
		"same-provider repeats must not duplicate that provider's name in Source")
	require.Equal(t, "service1", byTitle["Drink more still water"].Source)
}

func TestDedupe_CollapsesAcrossProviders(t *testing.T) {
	in := []domain.Recommendation{
		rec("Go for a physical check up", "service1", 0.05),
		rec("Go for a physical check up", "service2", 0.362),
		rec("Walk more", "service1", 0.29),
	}

	got := NewExactTitleDeduper().Dedupe(in)

	require.Len(t, got, 2)
	byTitle := indexByTitle(got)
	require.InDelta(t, 0.362, byTitle["Go for a physical check up"].NormScore, 0.0001,
		"the higher-scoring cross-provider instance's score must survive")
	require.Equal(t, "service1, service2", byTitle["Go for a physical check up"].Source,
		"both contributing providers must be recorded, not only the winner's, in first-seen order")
}

// TestDedupe_CrossProviderWinnerWithoutDetailsGetsLoserDetails is the
// defect this dedupe fix addresses. service1 items have no details field at
// all (Details is always ""), while service2 carries real details for the
// same tip. When the detail-less service1 instance wins on NormScore, its
// Details must not stay empty and the losing service2 instance's
// contribution must not vanish from Source — both were verified live:
// production returned {"title":"Don't eat carbs!","details":"","source":
// "service1","score":0.96} for a tip service2 also reports, with details,
// at a lower score.
func TestDedupe_CrossProviderWinnerWithoutDetailsGetsLoserDetails(t *testing.T) {
	winner := rec("Don't eat carbs!", "service1", 0.96)
	winner.Details = "" // service1's wire shape has no details field at all
	loser := rec("Don't eat carbs!", "service2", 0.33)
	loser.Details = "Carbs spike blood sugar; cut refined carbs first."

	got := NewExactTitleDeduper().Dedupe([]domain.Recommendation{winner, loser})

	require.Len(t, got, 1)
	require.InDelta(t, 0.96, got[0].NormScore, 0.0001, "highest score still wins")
	require.Equal(t, "Carbs spike blood sugar; cut refined carbs first.", got[0].Details,
		"the detail-less winner must inherit the losing duplicate's details")
	require.Equal(t, "service1, service2", got[0].Source,
		"both providers that independently recommended this tip must be recorded")
}

// TestDedupe_WinnerWithOwnDetailsIsNotOverwritten guards the other half of
// the same fix: when the winner already has non-empty Details, a duplicate
// must never clobber them, even though Source still grows to list every
// contributing provider.
func TestDedupe_WinnerWithOwnDetailsIsNotOverwritten(t *testing.T) {
	winner := rec("Walk more", "service2", 0.9)
	winner.Details = "Aim for 8000 steps."
	loser := rec("Walk more", "service1", 0.2)
	loser.Details = "" // service1 never has details

	got := NewExactTitleDeduper().Dedupe([]domain.Recommendation{winner, loser})

	require.Len(t, got, 1)
	require.Equal(t, "Aim for 8000 steps.", got[0].Details, "winner's own details must survive untouched")
	require.Equal(t, "service2, service1", got[0].Source, "first-seen provider order must be preserved")
}

func TestDedupe_KeepsDistinctTitlesUntouched(t *testing.T) {
	in := []domain.Recommendation{
		rec("Walk more", "service1", 0.4),
		rec("Drink water", "service2", 0.9),
	}
	got := NewExactTitleDeduper().Dedupe(in)
	require.Len(t, got, 2)
}

func TestDedupe_PreservesFirstSeenOrderForDeterminism(t *testing.T) {
	in := []domain.Recommendation{
		rec("B", "service1", 0.1),
		rec("A", "service1", 0.9),
		rec("B", "service2", 0.8), // higher score, but "B" was first seen second overall
	}
	got := NewExactTitleDeduper().Dedupe(in)
	require.Equal(t, []string{"B", "A"}, []string{got[0].Title, got[1].Title})
	require.InDelta(t, 0.8, got[0].NormScore, 0.0001, "highest score for B must still win")
}

func TestDedupe_EmptyInput(t *testing.T) {
	require.Empty(t, NewExactTitleDeduper().Dedupe(nil))
}

func indexByTitle(rs []domain.Recommendation) map[string]domain.Recommendation {
	out := make(map[string]domain.Recommendation, len(rs))
	for _, r := range rs {
		out[r.Title] = r
	}
	return out
}
