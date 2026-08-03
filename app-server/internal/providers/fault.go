package providers

import (
	"context"
	"errors"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
	"github.com/funwithactivity/funwithactivity/app-server/internal/faults"
)

// faultyProvider wraps any Provider and, when the request context asks for
// it by name, simulates a failure. It implements the same interface, so the
// aggregator cannot tell the difference — which is the point: the demo
// exercises the real resilience path, not a mock of it.
type faultyProvider struct{ inner Provider }

// WithFaults decorates a provider with demo fault injection.
func WithFaults(inner Provider) Provider { return &faultyProvider{inner: inner} }

func (f *faultyProvider) Name() string              { return f.inner.Name() }
func (f *faultyProvider) Requires() domain.FieldSet { return f.inner.Requires() }
func (f *faultyProvider) BaseURL() string           { return f.inner.BaseURL() }

func (f *faultyProvider) Fetch(ctx context.Context, m domain.Measurements) ([]domain.Recommendation, error) {
	switch faults.For(ctx, f.inner.Name()) {
	case faults.ModeError:
		return nil, &domain.ProviderError{
			Provider: f.inner.Name(),
			Code:     503,
			Message:  "simulated provider outage",
			Kind:     domain.KindTransient,
		}

	case faults.ModeTimeout:
		// Block until the caller's deadline fires. This exercises the real
		// per-provider context.WithTimeout path in the aggregator.
		<-ctx.Done()
		return nil, ctx.Err()

	case faults.ModeMalformed:
		return nil, errors.New("simulated malformed response: invalid character 'n'")

	default:
		return f.inner.Fetch(ctx, m)
	}
}
