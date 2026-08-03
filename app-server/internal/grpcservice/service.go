// Package grpcservice is the only package that maps domain types onto proto
// messages. Keeping the mapping here is what lets the domain model change
// without touching the wire contract, and vice versa.
package grpcservice

import (
	"context"
	"time"

	recommendationsv1 "github.com/funwithactivity/funwithactivity/api/gen/go/funwithactivity/api"
	"github.com/funwithactivity/funwithactivity/app-server/internal/aggregator"
	"github.com/funwithactivity/funwithactivity/app-server/internal/analytics"
	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
	"github.com/funwithactivity/funwithactivity/app-server/internal/faults"
	"google.golang.org/grpc/metadata"
)

type Server struct {
	recommendationsv1.UnimplementedRecommendationsServiceServer
	agg *aggregator.Aggregator
}

func New(agg *aggregator.Aggregator) *Server { return &Server{agg: agg} }

func (s *Server) GetRecommendations(
	ctx context.Context,
	req *recommendationsv1.GetRecommendationsRequest,
) (*recommendationsv1.GetRecommendationsResponse, error) {

	ctx = faults.WithModes(ctx, parseFaults(req.GetFaults()))

	start := time.Now()
	result, err := s.agg.Aggregate(ctx, toDomain(req.GetMeasurements()))
	if err != nil {
		return nil, err
	}

	analytics.Emit(ctx, analytics.Event{
		Name:          "recommendation_requested",
		AnalyticsID:   analyticsIDFrom(ctx),
		RequestID:     requestIDFrom(ctx),
		ProviderCount: len(result.Statuses),
		ResultCount:   len(result.Recommendations),
		LatencyMs:     time.Since(start).Milliseconds(),
		Degraded:      isDegraded(result.Statuses),
	})

	return &recommendationsv1.GetRecommendationsResponse{
		Recommendations: toProtoRecommendations(result.Recommendations),
		Statuses:        toProtoStatuses(result.Statuses),
	}, nil
}

func toDomain(m *recommendationsv1.Measurements) domain.Measurements {
	if m == nil {
		return domain.Measurements{}
	}
	out := domain.Measurements{HeightCm: m.GetHeightCm(), WeightKg: m.GetWeightKg()}
	if ts := m.GetBirthDateUnix(); ts != 0 {
		t := time.Unix(ts, 0).UTC()
		out.BirthDate = &t
	}
	return out
}

// toProtoRecommendations deliberately drops RawScore and NormScore. Only the
// final score is contract; exposing the others would freeze the ranker.
func toProtoRecommendations(in []domain.Recommendation) []*recommendationsv1.Recommendation {
	out := make([]*recommendationsv1.Recommendation, 0, len(in))
	for _, r := range in {
		out = append(out, &recommendationsv1.Recommendation{
			Title:   r.Title,
			Details: r.Details,
			Source:  r.Source,
			Score:   r.FinalScore,
		})
	}
	return out
}

func toProtoStatuses(in []aggregator.ProviderStatus) []*recommendationsv1.ProviderStatus {
	out := make([]*recommendationsv1.ProviderStatus, 0, len(in))
	for _, s := range in {
		out = append(out, &recommendationsv1.ProviderStatus{
			Name:      s.Name,
			Ok:        s.OK,
			Skipped:   s.Skipped,
			Error:     s.Error,
			Count:     int32(s.Count),
			LatencyMs: s.LatencyMs,
		})
	}
	return out
}

func parseFaults(in map[string]string) map[string]faults.Mode {
	out := make(map[string]faults.Mode, len(in))
	for k, v := range in {
		if m := faults.Parse(v); m != faults.ModeNone {
			out[k] = m
		}
	}
	return out
}

func isDegraded(ss []aggregator.ProviderStatus) bool {
	for _, s := range ss {
		if !s.OK && !s.Skipped {
			return true
		}
	}
	return false
}

func requestIDFrom(ctx context.Context) string { return firstMD(ctx, "x-request-id") }

// analyticsIDFrom reads the pseudonymous id the caller supplies. It is never
// derived from anything identifying on this side of the boundary.
func analyticsIDFrom(ctx context.Context) string { return firstMD(ctx, "x-analytics-id") }

func firstMD(ctx context.Context, key string) string {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return ""
	}
	if v := md.Get(key); len(v) > 0 {
		return v[0]
	}
	return ""
}
