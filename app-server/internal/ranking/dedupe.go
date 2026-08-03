package ranking

import (
	"strings"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
)

// Deduper collapses recommendations that are really the same tip reported
// more than once. It runs on the merged, cross-provider set, after fan-out
// but before ranking, so both same-provider repeats (a single vendor
// response containing the same title several times) and cross-provider
// repeats (both vendors independently surfacing "Drink more still water")
// collapse into one entry each.
type Deduper interface {
	Dedupe([]domain.Recommendation) []domain.Recommendation
}

// ExactTitleDeduper treats two recommendations as duplicates when their
// Title matches exactly (case-sensitive, no normalisation). Live vendor
// responses have been observed to repeat identical titles verbatim within a
// single response and across both providers, so exact match is sufficient —
// there is no evidence of near-duplicate titles worth fuzzy-matching, and
// guessing at similarity thresholds would risk collapsing genuinely
// distinct tips.
type ExactTitleDeduper struct{}

func NewExactTitleDeduper() ExactTitleDeduper { return ExactTitleDeduper{} }

// group accumulates everything the surviving record for one title needs to
// carry, beyond just the highest-scoring instance itself: the two vendors
// carry different information (service1 has no Details field at all;
// service2 does), so whichever instance wins on score must not cause the
// other's Details — or the fact that it also recommended this tip — to be
// silently dropped.
type group struct {
	best                domain.Recommendation
	firstNonEmptyDetail string
	sources             []string
	sourceSeen          map[string]bool
}

// Dedupe keeps, for each distinct Title, the instance with the highest
// NormScore — the score on the common 0..1 axis both providers already
// share, so the comparison is meaningful across sources even before
// per-provider ranking weights are applied.
//
// Collapsing to the highest-scoring instance must not discard information
// only a lower-scoring duplicate carries:
//
//   - If the surviving (highest-scoring) instance has an empty Details, but
//     some other duplicate for the same title carried non-empty Details
//     (this happens whenever service1, which has no details field at all,
//     outscores service2 on the same tip), those details are carried onto
//     the survivor. The survivor's own non-empty Details, if it has one, is
//     never overwritten by another duplicate's.
//   - Source becomes every distinct provider that reported this title,
//     joined with ", " in first-seen order (e.g. "service1, service2"),
//     rather than only the winner's own Source — two providers
//     independently recommending the same tip is exactly the merge this
//     product exists to perform, and collapsing to a single Source hid it.
//     PrimarySource is set to the winner's own (pre-merge) Source and is
//     what Ranker keys per-provider weight from — see the seam note on
//     domain.Recommendation. Source itself is display-only from here on;
//     do not use it for weight lookups downstream.
//
// The surviving instances are returned in first-seen order from the input,
// which keeps output deterministic (never influenced by Go's randomised map
// iteration) and preserves the fan-out order the ranker's stable sort relies
// on for ties. Source's first-seen provider order is independently
// deterministic for the same reason: it only ever depends on input order,
// never on map iteration.
func (ExactTitleDeduper) Dedupe(in []domain.Recommendation) []domain.Recommendation {
	if len(in) == 0 {
		return in
	}

	groups := make(map[string]*group, len(in))
	order := make([]string, 0, len(in))
	for _, r := range in {
		g, seen := groups[r.Title]
		if !seen {
			g = &group{best: r, sourceSeen: make(map[string]bool, 2)}
			groups[r.Title] = g
			order = append(order, r.Title)
		} else if r.NormScore > g.best.NormScore {
			g.best = r
		}

		if g.firstNonEmptyDetail == "" && r.Details != "" {
			g.firstNonEmptyDetail = r.Details
		}
		if !g.sourceSeen[r.Source] {
			g.sourceSeen[r.Source] = true
			g.sources = append(g.sources, r.Source)
		}
	}

	out := make([]domain.Recommendation, 0, len(order))
	for _, title := range order {
		g := groups[title]
		rec := g.best
		if rec.Details == "" {
			rec.Details = g.firstNonEmptyDetail
		}
		// PrimarySource must be captured from the winner's own Source
		// before Source is overwritten below with the joined display
		// string — it is the ranking weight key, Source is not.
		rec.PrimarySource = rec.Source
		rec.Source = strings.Join(g.sources, ", ")
		out = append(out, rec)
	}
	return out
}
