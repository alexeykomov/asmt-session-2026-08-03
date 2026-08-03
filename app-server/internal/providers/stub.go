package providers

import (
	"context"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
)

// StubProvider returns canned recommendations instead of calling a real
// upstream. It exists so the demo has data to show when the customer's
// brief shipped without real Service 1/2 endpoint URLs, and so the demo
// does not depend on third-party vendors the brief itself warns offer "no
// guarantees on stability and availability".
//
// Stubs activate only when USE_STUB_PROVIDERS=true is set explicitly — see
// DefaultProviders in registry.go. They must never engage automatically
// just because a real provider's URL is empty or a real call failed; that
// would silently substitute fabricated data for a real failure.
type StubProvider struct {
	name     string
	requires domain.FieldSet
	recs     []domain.Recommendation
}

// NewService1Stub stands in for Service 1: same input requirements
// (height + weight, no birth date), scores expressed as the same 0..1
// confidence Service 1 itself returns.
func NewService1Stub() *StubProvider {
	return &StubProvider{
		name:     "service1-stub",
		requires: domain.Of(domain.FieldHeight, domain.FieldWeight),
		recs: []domain.Recommendation{
			{Title: "Walk more", Source: "service1-stub", RawScore: 0.4, NormScore: 0.4},
			{Title: "Drink more water", Source: "service1-stub", RawScore: 0.9, NormScore: 0.9},
			{Title: "Improve your sleep schedule", Source: "service1-stub", RawScore: 0.65, NormScore: 0.65},
		},
	}
}

// NewService2Stub stands in for Service 2: same input requirements
// (height + weight + birth date), scores expressed as the same 1..1000
// priority Service 2 itself returns, normalised the same way.
func NewService2Stub() *StubProvider {
	return &StubProvider{
		name:     "service2-stub",
		requires: domain.Of(domain.FieldHeight, domain.FieldWeight, domain.FieldBirthDate),
		recs: []domain.Recommendation{
			{Title: "Have more workouts per day", Details: "Workouts help.", Source: "service2-stub",
				RawScore: 750, NormScore: 750 / service2MaxPriority},
			{Title: "Aim for 7–8 hours of sleep", Details: "Sleep is when the body recovers.", Source: "service2-stub",
				RawScore: 880, NormScore: 880 / service2MaxPriority},
			{Title: "Add 20 push-ups to your morning", Details: "Small habits compound.", Source: "service2-stub",
				RawScore: 380, NormScore: 380 / service2MaxPriority},
		},
	}
}

func (p *StubProvider) Name() string              { return p.name }
func (p *StubProvider) Requires() domain.FieldSet { return p.requires }

// BaseURL reports the stub's own identity, never a real vendor URL — a stub
// claiming a real vendor endpoint would show fabricated configuration on
// the Source detail screen, exactly what field 7 exists to end.
func (p *StubProvider) BaseURL() string { return "stub:" + p.name }

// Fetch returns the canned recommendations, honouring ctx cancellation so
// the fault-injection wrapper and per-provider timeout still behave
// correctly when a stub is wrapped in WithFaults.
func (p *StubProvider) Fetch(ctx context.Context, _ domain.Measurements) ([]domain.Recommendation, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	out := make([]domain.Recommendation, len(p.recs))
	copy(out, p.recs)
	return out, nil
}
