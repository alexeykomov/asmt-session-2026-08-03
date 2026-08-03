// Package analytics emits product-analytics events. Everything here crosses
// into the analytics plane, which is a separate AWS account with separate
// KMS keys in the target architecture — so nothing in an Event may be PHI.
//
// The struct has no field capable of carrying a measurement, a birth date,
// or recommendation text. That is deliberate: the boundary is enforced by
// the type, not by reviewer discipline.
package analytics

import (
	"context"
	"encoding/json"
	"log/slog"
)

type Event struct {
	Name          string `json:"event"`
	AnalyticsID   string `json:"analytics_id"` // pseudonymous; maps to a user only in the PHI plane
	RequestID     string `json:"request_id"`
	ProviderCount int    `json:"provider_count"`
	ResultCount   int    `json:"result_count"`
	LatencyMs     int64  `json:"latency_ms"`
	Degraded      bool   `json:"degraded"`
}

func Format(e Event) string {
	b, err := json.Marshal(e)
	if err != nil {
		return `{"event":"analytics_marshal_failed"}`
	}
	return string(b)
}

// Emit writes the event. In production this is a producer into the analytics
// plane; for the skeleton it is a structured log line, which is enough to
// show the boundary on screen.
func Emit(ctx context.Context, e Event) {
	slog.InfoContext(ctx, "analytics", "event", Format(e))
}
