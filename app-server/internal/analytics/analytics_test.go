package analytics

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestEvent_ContainsNoPHI(t *testing.T) {
	line := Format(Event{
		Name:          "recommendation_requested",
		AnalyticsID:   "a7f3c19e",
		RequestID:     "req-1",
		ProviderCount: 2,
		LatencyMs:     142,
		Degraded:      true,
		ResultCount:   5,
	})

	// The analytics plane must never see a measurement, a birth date, or a
	// recommendation body. This test is the executable form of that boundary.
	for _, forbidden := range []string{"height", "weight", "birth", "184", "84", "Walk more"} {
		require.NotContains(t, strings.ToLower(line), strings.ToLower(forbidden))
	}
	require.Contains(t, line, "recommendation_requested")
	require.Contains(t, line, "a7f3c19e")
}
