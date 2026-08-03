package charts

import (
	"math"
	"reflect"
	"testing"
	"time"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
)

func profile() domain.Measurements {
	dob := time.Date(1983, 5, 29, 0, 0, 0, 0, time.UTC)
	return domain.Measurements{HeightCm: 175, WeightKg: 70, BirthDate: &dob}
}

// The property the demo depends on: the same profile must produce byte-equal
// charts every time. Without this the screen changes under the presenter and
// a screenshot stops matching the app.
func TestGenerateIsDeterministic(t *testing.T) {
	a := Generate(profile())
	b := Generate(profile())
	if !reflect.DeepEqual(a, b) {
		t.Fatalf("Generate is not deterministic for the same measurements")
	}
}

// The other half of the same property: different profiles must actually look
// different, or "edit the profile and watch the charts move" is not a real
// demo beat.
func TestGenerateVariesByProfile(t *testing.T) {
	dob := time.Date(1995, 2, 2, 0, 0, 0, 0, time.UTC)
	other := domain.Measurements{HeightCm: 190, WeightKg: 95, BirthDate: &dob}

	if reflect.DeepEqual(Generate(profile()), Generate(other)) {
		t.Fatalf("two different profiles produced identical charts")
	}
}

func TestGenerateShape(t *testing.T) {
	got := Generate(profile())
	if len(got) != 3 {
		t.Fatalf("charts = %d, want 3", len(got))
	}

	wantIDs := []string{IDSteps, IDSleep, IDActiveMinutes}
	for i, want := range wantIDs {
		if got[i].ID != want {
			t.Errorf("charts[%d].ID = %q, want %q", i, got[i].ID, want)
		}
		if got[i].Title == "" {
			t.Errorf("charts[%d] (%s) has no title", i, got[i].ID)
		}
		if len(got[i].Series) == 0 {
			t.Errorf("charts[%d] (%s) has no series", i, got[i].ID)
		}
	}
}

// A bar chart whose series length disagrees with its category axis cannot be
// drawn without either dropping data or reading past the end of the axis.
func TestBarSeriesMatchCategories(t *testing.T) {
	for _, c := range Generate(profile()) {
		if c.Type == TypePie {
			continue
		}
		for _, s := range c.Series {
			if len(s.Values) != len(c.Categories) {
				t.Errorf("%s/%s: %d values for %d categories",
					c.ID, s.Key, len(s.Values), len(c.Categories))
			}
		}
	}
}

// A pie whose slices do not close is a visibly wrong chart, and floating
// point will not close it by luck — the generator assigns the remainder to
// the last slice precisely so this holds.
func TestSleepPieSumsTo100(t *testing.T) {
	for _, m := range []domain.Measurements{
		profile(),
		{HeightCm: 150, WeightKg: 45},
		{HeightCm: 200, WeightKg: 120},
		{}, // nothing supplied at all
	} {
		var total float64
		for _, c := range Generate(m) {
			if c.ID != IDSleep {
				continue
			}
			for _, s := range c.Series {
				if len(s.Values) != 1 {
					t.Fatalf("pie series %s has %d values, want 1", s.Key, len(s.Values))
				}
				total += s.Values[0]
			}
		}
		if math.Abs(total-100) > 0.05 {
			t.Errorf("sleep slices total %.4f for %+v, want 100", total, m)
		}
	}
}

// Negative steps or negative minutes are nonsense that a chart will happily
// render as a bar pointing the wrong way.
func TestValuesAreNonNegative(t *testing.T) {
	for _, m := range []domain.Measurements{
		profile(),
		{HeightCm: 140, WeightKg: 200}, // extreme enough to drive the base term negative
		{},
	} {
		for _, c := range Generate(m) {
			for _, s := range c.Series {
				for i, v := range s.Values {
					if v < 0 {
						t.Errorf("%s/%s[%d] = %v, want >= 0 (profile %+v)", c.ID, s.Key, i, v, m)
					}
				}
			}
		}
	}
}

// Measurements are optional by design — the data-minimisation gate exists
// because a user may decline to supply them. Charts must degrade to a
// baseline profile rather than empty or panic.
func TestGenerateWithNoMeasurements(t *testing.T) {
	got := Generate(domain.Measurements{})
	if len(got) != 3 {
		t.Fatalf("charts = %d for empty measurements, want 3", len(got))
	}
	for _, c := range got {
		for _, s := range c.Series {
			if len(s.Values) == 0 {
				t.Errorf("%s/%s has no values for an empty profile", c.ID, s.Key)
			}
		}
	}
}

// Every series key must be non-empty and unique within its chart: clients map
// key to a colour asset, so a duplicate or blank key means two series drawn
// the same colour with no way to tell them apart.
func TestSeriesKeysAreUniqueWithinChart(t *testing.T) {
	for _, c := range Generate(profile()) {
		seen := map[string]bool{}
		for _, s := range c.Series {
			if s.Key == "" {
				t.Errorf("%s has a series with an empty key", c.ID)
			}
			if seen[s.Key] {
				t.Errorf("%s has duplicate series key %q", c.ID, s.Key)
			}
			seen[s.Key] = true
		}
	}
}
