package domain

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestCmToFeet(t *testing.T) {
	// The brief's own example: 184.0 cm is presented to Service 2 as 6.036 ft.
	require.InDelta(t, 6.036, CmToFeet(184.0), 0.001)
}

func TestKgToPounds(t *testing.T) {
	require.InDelta(t, 185.188, KgToPounds(84.0), 0.01)
}

func TestConversionRoundTrip(t *testing.T) {
	for _, cm := range []float64{150, 170.5, 184, 210} {
		require.InDelta(t, cm, CmToFeet(cm)*30.48, 0.0001)
	}
	for _, kg := range []float64{50, 72.3, 84, 120} {
		require.InDelta(t, kg, KgToPounds(kg)/2.2046226218, 0.0001)
	}
}

func TestFieldSet_SatisfiedBy_AllPresent(t *testing.T) {
	dob := time.Unix(1615876858, 0)
	m := Measurements{HeightCm: 184, WeightKg: 84, BirthDate: &dob}
	require.True(t, Of(FieldHeight, FieldWeight, FieldBirthDate).SatisfiedBy(m))
}

func TestFieldSet_SatisfiedBy_MissingBirthDate(t *testing.T) {
	m := Measurements{HeightCm: 184, WeightKg: 84}
	require.True(t, Of(FieldHeight, FieldWeight).SatisfiedBy(m),
		"a provider that does not need DOB must still be satisfied")
	require.False(t, Of(FieldHeight, FieldWeight, FieldBirthDate).SatisfiedBy(m),
		"a provider that needs DOB must be skipped when it is absent")
}

func TestFieldSet_SatisfiedBy_ZeroHeight(t *testing.T) {
	m := Measurements{WeightKg: 84}
	require.False(t, Of(FieldHeight).SatisfiedBy(m))
}
