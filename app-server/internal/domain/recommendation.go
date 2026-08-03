package domain

// Recommendation is the canonical output. RawScore is the provider's own
// number in its own scale; NormScore is that number mapped onto 0..1;
// FinalScore is what the Ranker produced. Only FinalScore crosses the wire.
//
// Source vs. PrimarySource: after ranking.Deduper merges same-title
// duplicates from multiple providers, Source becomes a joined, purely
// display string (e.g. "service1, service2") — it lists everyone who
// recommended the tip, but that is not something a weight table can key on.
// PrimarySource is the single provider whose instance actually won the
// dedupe (i.e. what Source itself held before merging), and it is what
// Ranker resolves per-provider weight from. Do not re-merge these two: a
// weight lookup against the joined Source would silently default to 1.0 for
// every merged record, discarding the losing/winning providers' configured
// trust weights.
type Recommendation struct {
	Title         string
	Details       string
	Source        string
	PrimarySource string
	RawScore      float64
	NormScore     float64
	FinalScore    float64
}
