package providers

import (
	"context"
	"testing"
	"time"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
	"github.com/funwithactivity/funwithactivity/app-server/internal/faults"
	"github.com/stretchr/testify/require"
)

type stubProvider struct{ name string }

func (s *stubProvider) Name() string              { return s.name }
func (s *stubProvider) Requires() domain.FieldSet { return domain.Of(domain.FieldHeight) }
func (s *stubProvider) Fetch(context.Context, domain.Measurements) ([]domain.Recommendation, error) {
	return []domain.Recommendation{{Title: "real", Source: s.name, NormScore: 0.5}}, nil
}

func TestFaults_PassThroughWhenNoModeSet(t *testing.T) {
	p := WithFaults(&stubProvider{name: "s1"})
	got, err := p.Fetch(context.Background(), domain.Measurements{HeightCm: 184})
	require.NoError(t, err)
	require.Len(t, got, 1)
}

func TestFaults_ErrorMode(t *testing.T) {
	ctx := faults.WithModes(context.Background(), map[string]faults.Mode{"s1": faults.ModeError})
	_, err := WithFaults(&stubProvider{name: "s1"}).Fetch(ctx, domain.Measurements{HeightCm: 184})
	require.Error(t, err)
}

func TestFaults_TimeoutModeRespectsContextDeadline(t *testing.T) {
	ctx := faults.WithModes(context.Background(), map[string]faults.Mode{"s1": faults.ModeTimeout})
	ctx, cancel := context.WithTimeout(ctx, 30*time.Millisecond)
	defer cancel()

	start := time.Now()
	_, err := WithFaults(&stubProvider{name: "s1"}).Fetch(ctx, domain.Measurements{HeightCm: 184})

	require.Error(t, err)
	require.Less(t, time.Since(start), 200*time.Millisecond,
		"timeout fault must end when the caller's deadline fires, not hang")
}

func TestFaults_OnlyAffectsNamedProvider(t *testing.T) {
	ctx := faults.WithModes(context.Background(), map[string]faults.Mode{"s2": faults.ModeError})
	got, err := WithFaults(&stubProvider{name: "s1"}).Fetch(ctx, domain.Measurements{HeightCm: 184})
	require.NoError(t, err)
	require.Len(t, got, 1)
}

func TestFaults_ParseRejectsUnknown(t *testing.T) {
	require.Equal(t, faults.ModeError, faults.Parse("error"))
	require.Equal(t, faults.ModeTimeout, faults.Parse("timeout"))
	require.Equal(t, faults.ModeMalformed, faults.Parse("malformed"))
	require.Equal(t, faults.ModeNone, faults.Parse("rm -rf"))
}
