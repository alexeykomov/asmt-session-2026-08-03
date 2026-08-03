package providers

import (
	"context"
	"testing"
	"time"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
	"github.com/stretchr/testify/require"
)

func TestStub_NamesAreDistinctFromRealProviders(t *testing.T) {
	require.Equal(t, "service1-stub", NewService1Stub().Name())
	require.Equal(t, "service2-stub", NewService2Stub().Name())
}

func TestStub_BaseURLReportsStubIdentityHonestly(t *testing.T) {
	// Stubs must never claim a real vendor URL — that would show
	// fabricated configuration on the Source detail screen.
	require.Equal(t, "stub:service1-stub", NewService1Stub().BaseURL())
	require.Equal(t, "stub:service2-stub", NewService2Stub().BaseURL())
	require.NotContains(t, NewService1Stub().BaseURL(), "http")
	require.NotContains(t, NewService2Stub().BaseURL(), "http")
}

func TestStub_RequiresMirrorsRealProviders(t *testing.T) {
	withDOB := domain.Measurements{HeightCm: 184, WeightKg: 84, BirthDate: dobPtr()}
	withoutDOB := domain.Measurements{HeightCm: 184, WeightKg: 84}

	s1 := NewService1Stub().Requires()
	require.True(t, s1.SatisfiedBy(withoutDOB), "service1 stub must not require a birth date")
	require.True(t, s1.SatisfiedBy(withDOB))

	s2 := NewService2Stub().Requires()
	require.False(t, s2.SatisfiedBy(withoutDOB), "service2 stub must be skipped when birth date is absent")
	require.True(t, s2.SatisfiedBy(withDOB))
}

func TestStub_Service1ScoresAreNativeConfidenceScale(t *testing.T) {
	got, err := NewService1Stub().Fetch(context.Background(), domain.Measurements{HeightCm: 184, WeightKg: 84})
	require.NoError(t, err)
	require.Len(t, got, 3)

	byTitle := recsByTitle(got)
	walkMore := byTitle["Walk more"]
	require.Equal(t, 0.4, walkMore.RawScore, "confidence 0.4 must be left unchanged")
	require.Equal(t, 0.4, walkMore.NormScore)
	require.Empty(t, walkMore.Details, "service1's shape has no details field")
	require.Equal(t, "service1-stub", walkMore.Source)
}

func TestStub_Service2ScoresNormalisePriorityScale(t *testing.T) {
	got, err := NewService2Stub().Fetch(context.Background(), domain.Measurements{HeightCm: 184, WeightKg: 84, BirthDate: dobPtr()})
	require.NoError(t, err)
	require.Len(t, got, 3)

	byTitle := recsByTitle(got)
	workouts := byTitle["Have more workouts per day"]
	require.Equal(t, 750.0, workouts.RawScore)
	require.InDelta(t, 0.75, workouts.NormScore, 0.0001, "priority 750 must normalise to 0.75")
	require.NotEmpty(t, workouts.Details, "service2 entries carry details text")
	require.Equal(t, "service2-stub", workouts.Source)
}

func TestStub_FetchRespectsCancelledContext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	_, err := NewService1Stub().Fetch(ctx, domain.Measurements{HeightCm: 184, WeightKg: 84})
	require.Error(t, err)

	_, err = NewService2Stub().Fetch(ctx, domain.Measurements{HeightCm: 184, WeightKg: 84, BirthDate: dobPtr()})
	require.Error(t, err)
}

func TestStub_FetchReturnsPromptlyOnDeadlineExceeded(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Nanosecond)
	defer cancel()
	time.Sleep(time.Millisecond) // ensure the deadline has actually passed

	start := time.Now()
	_, err := NewService1Stub().Fetch(ctx, domain.Measurements{HeightCm: 184, WeightKg: 84})
	require.Error(t, err)
	require.Less(t, time.Since(start), 50*time.Millisecond)
}

func dobPtr() *time.Time {
	dob := time.Unix(1615876858, 0)
	return &dob
}

func recsByTitle(recs []domain.Recommendation) map[string]domain.Recommendation {
	out := make(map[string]domain.Recommendation, len(recs))
	for _, r := range recs {
		out[r.Title] = r
	}
	return out
}
