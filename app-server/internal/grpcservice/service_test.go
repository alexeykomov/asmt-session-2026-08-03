package grpcservice

import (
	"testing"

	"github.com/funwithactivity/funwithactivity/app-server/internal/aggregator"
	"github.com/stretchr/testify/require"
)

func TestIsDegraded(t *testing.T) {
	cases := []struct {
		name     string
		statuses []aggregator.ProviderStatus
		want     bool
	}{
		{
			name: "all providers ok",
			statuses: []aggregator.ProviderStatus{
				{Name: "service1", OK: true},
				{Name: "service2", OK: true},
			},
			want: false,
		},
		{
			name: "one provider genuinely failed",
			statuses: []aggregator.ProviderStatus{
				{Name: "service1", OK: false, Skipped: false, Error: "simulated provider outage"},
			},
			want: true,
		},
		{
			name: "one provider skipped for declined input, not degraded",
			statuses: []aggregator.ProviderStatus{
				{Name: "service2", OK: false, Skipped: true, Error: "required measurements not supplied"},
			},
			want: false,
		},
		{
			name: "mix of one skipped and one genuinely failed is degraded",
			statuses: []aggregator.ProviderStatus{
				{Name: "service1", OK: false, Error: "simulated provider outage"},
				{Name: "service2", OK: false, Skipped: true, Error: "required measurements not supplied"},
			},
			want: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.want, isDegraded(tc.statuses))
		})
	}
}
