package grpcservice

import (
	"context"

	recommendationsv1 "github.com/funwithactivity/funwithactivity/api/gen/go/funwithactivity/api"
	"github.com/funwithactivity/funwithactivity/app-server/internal/charts"
)

// GetHealthCharts serves the clients' Charts tab.
//
// Deliberately not part of the recommendation path: it calls no provider,
// reports no ProviderStatus, and cannot be degraded by a vendor outage. The
// fan-out's timeouts, fault injection and skipped/degraded classification are
// all irrelevant here, and routing this through the aggregator to reuse them
// would couple a drawing feature to the vendor integration for no benefit.
//
// Returns no error for a valid request. charts.Generate has no failure mode —
// absent measurements produce a baseline profile rather than an empty
// response — so there is no error branch for three clients to render.
func (s *Server) GetHealthCharts(
	ctx context.Context,
	req *recommendationsv1.GetHealthChartsRequest,
) (*recommendationsv1.HealthChartsResponse, error) {

	generated := charts.Generate(toDomain(req.GetMeasurements()))

	return &recommendationsv1.HealthChartsResponse{
		Charts: toProtoCharts(generated),
	}, nil
}

func toProtoCharts(in []charts.Chart) []*recommendationsv1.Chart {
	out := make([]*recommendationsv1.Chart, 0, len(in))
	for _, c := range in {
		out = append(out, &recommendationsv1.Chart{
			Id:         c.ID,
			Title:      c.Title,
			Type:       toProtoChartType(c.Type),
			Categories: c.Categories,
			Series:     toProtoSeries(c.Series),
		})
	}
	return out
}

func toProtoSeries(in []charts.Series) []*recommendationsv1.Series {
	out := make([]*recommendationsv1.Series, 0, len(in))
	for _, s := range in {
		out = append(out, &recommendationsv1.Series{
			Key:    s.Key,
			Label:  s.Label,
			Values: s.Values,
		})
	}
	return out
}

// toProtoChartType maps the domain enum onto the wire enum. Written as an
// explicit switch rather than a numeric cast: the two enums happen to agree
// today, and a cast would silently start lying the first time either gains a
// member out of step with the other.
func toProtoChartType(t charts.Type) recommendationsv1.ChartType {
	switch t {
	case charts.TypeBar:
		return recommendationsv1.ChartType_CHART_TYPE_BAR
	case charts.TypePie:
		return recommendationsv1.ChartType_CHART_TYPE_PIE
	case charts.TypeGroupedBar:
		return recommendationsv1.ChartType_CHART_TYPE_GROUPED_BAR
	default:
		return recommendationsv1.ChartType_CHART_TYPE_UNSPECIFIED
	}
}
