// Package charts generates the health chart data behind the clients' Charts
// tab.
//
// The data is synthetic and deliberately so: this proof of concept has no
// telemetry pipeline, no device integration and no store. The production
// design puts real samples in ClickHouse #1 and projects the latest values
// out to the read path (see docs/architecture-diagrams.md, diagram 4); this
// package occupies exactly that seam so the clients can be built against the
// shape they will consume.
//
// Two properties matter more than realism:
//
// Deterministic. The same measurements always produce the same charts, so a
// demo does not change under the presenter mid-sentence and a screenshot
// taken yesterday still matches the screen today. Every value derives from a
// seed built out of the measurements — there is no time source and no
// randomness here.
//
// Plausible for the profile. Values are shaped by height, weight and age so
// two different profiles produce visibly different charts. That is what makes
// "change the profile, watch the charts move" a real demo beat rather than a
// claim.
//
// The clients label this as sample data on screen. This package does not
// pretend otherwise, and nothing here should ever be described as measured.
package charts

import (
	"hash/fnv"
	"math"
	"time"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
)

// Type identifies how a chart should be drawn. The wire carries this so a
// client never has to infer a shape from a chart's id.
type Type int

const (
	TypeUnspecified Type = iota
	TypeBar
	TypePie
	TypeGroupedBar
)

// Series is one named run of values. Key is the stable mapping handle a
// client turns into a colour; Label is display text and carries no meaning.
type Series struct {
	Key    string
	Label  string
	Values []float64
}

// Chart is one drawable chart: a title, a shape, the category axis, and the
// series plotted against it.
type Chart struct {
	ID         string
	Title      string
	Type       Type
	Categories []string
	Series     []Series
}

// Chart ids. Exported because the grpcservice mapping and the tests both
// refer to them, and a typo in a string literal is not worth debugging.
const (
	IDSteps         = "steps"
	IDSleep         = "sleep"
	IDActiveMinutes = "active_minutes"
)

// weekdays is the category axis for the two seven-day charts. Fixed rather
// than derived from the current date: a chart whose labels shift at midnight
// makes yesterday's screenshot disagree with today's screen for no reason
// anyone can see.
var weekdays = []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}

// Generate returns the three charts for a profile.
//
// Never returns an error and never returns nil: a Charts tab that can fail is
// a Charts tab that needs a second error path on three clients, and there is
// nothing here that can legitimately fail. Zero or absent measurements
// produce the baseline profile rather than an empty response.
func Generate(m domain.Measurements) []Chart {
	seed := seedFor(m)
	return []Chart{
		stepsChart(seed, m),
		sleepChart(seed),
		activeMinutesChart(seed, m),
	}
}

// seedFor derives a stable seed from the measurements. Rounded before
// hashing so that a trivially different weight — 70.0 versus 70.0000001,
// which a float input can produce — does not redraw every chart.
func seedFor(m domain.Measurements) uint64 {
	h := fnv.New64a()
	var buf [3]int64
	buf[0] = int64(math.Round(m.HeightCm))
	buf[1] = int64(math.Round(m.WeightKg))
	buf[2] = 0
	if m.BirthDate != nil {
		buf[2] = m.BirthDate.Unix()
	}
	for _, v := range buf {
		var b [8]byte
		for i := 0; i < 8; i++ {
			b[i] = byte(v >> (8 * i))
		}
		_, _ = h.Write(b[:])
	}
	return h.Sum64()
}

// vary returns a deterministic value in [-1, 1] for slot i of the seed. This
// is the only source of shape in the generated data; there is no rand.
func vary(seed uint64, i int) float64 {
	x := seed ^ (uint64(i+1) * 0x9E3779B97F4A7C15)
	x ^= x >> 30
	x *= 0xBF58476D1CE4E5B9
	x ^= x >> 27
	// 53 bits, the exactly-representable range for float64.
	unit := float64(x>>11) / float64(uint64(1)<<53)
	return unit*2 - 1
}

// ageYears returns the profile's age, or 0 when no birth date was supplied —
// which is the whole point of the data-minimisation gate: a user may decline
// it, and everything downstream must cope rather than demand it.
func ageYears(m domain.Measurements) float64 {
	if m.BirthDate == nil {
		return 0
	}
	// Fixed reference rather than time.Now(): a chart that changes on a
	// birthday would break determinism for no user-visible benefit.
	const daysPerYear = 365.2425
	years := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC).Sub(*m.BirthDate).Hours() / 24 / daysPerYear
	if years < 0 || years > 120 {
		return 0
	}
	return years
}

// stepsChart is a seven-day bar chart. Heavier profiles trend slightly lower
// and older profiles lower still, which is enough to make two profiles look
// different without pretending to model anything.
func stepsChart(seed uint64, m domain.Measurements) Chart {
	base := 9000.0
	if m.WeightKg > 0 {
		base -= (m.WeightKg - 70) * 25
	}
	if age := ageYears(m); age > 0 {
		base -= (age - 35) * 30
	}
	if base < 3000 {
		base = 3000
	}

	values := make([]float64, len(weekdays))
	for i := range weekdays {
		v := base + vary(seed, i)*2200
		// Weekends read differently on every real step chart; without this
		// the bars look like noise rather than a week.
		if i >= 5 {
			v *= 1.15
		}
		values[i] = math.Round(math.Max(v, 0))
	}

	return Chart{
		ID:         IDSteps,
		Title:      "Steps, last 7 days",
		Type:       TypeBar,
		Categories: weekdays,
		Series:     []Series{{Key: "steps", Label: "Steps", Values: values}},
	}
}

// sleepChart is a pie of last night's sleep stages. Values are percentages
// and are normalised to total exactly 100 — a pie whose slices do not close
// is a visibly wrong chart, and floating point will not close it by luck.
func sleepChart(seed uint64) Chart {
	raw := []float64{
		22 + vary(seed, 10)*6,
		52 + vary(seed, 11)*8,
		18 + vary(seed, 12)*5,
		8 + vary(seed, 13)*3,
	}
	var total float64
	for i, v := range raw {
		if v < 1 {
			raw[i] = 1
		}
		total += raw[i]
	}

	keys := []string{"deep", "light", "rem", "awake"}
	labels := []string{"Deep", "Light", "REM", "Awake"}
	series := make([]Series, len(keys))
	var assigned float64
	for i := range keys {
		var pct float64
		if i == len(keys)-1 {
			// The last slice takes the remainder so rounding cannot leave
			// the pie at 99.9 or 100.1.
			pct = math.Round((100-assigned)*10) / 10
		} else {
			pct = math.Round(raw[i]/total*1000) / 10
			assigned += pct
		}
		series[i] = Series{Key: keys[i], Label: labels[i], Values: []float64{pct}}
	}

	return Chart{
		ID:         IDSleep,
		Title:      "Sleep stages, last night",
		Type:       TypePie,
		Categories: labels,
		Series:     series,
	}
}

// activeMinutesChart is a grouped bar: three intensity bands across the same
// seven days, so it reads against the steps chart above it.
func activeMinutesChart(seed uint64, m domain.Measurements) Chart {
	bands := []struct {
		key, label string
		base       float64
		slot       int
	}{
		{"light_activity", "Light", 42, 20},
		{"moderate", "Moderate", 24, 30},
		{"vigorous", "Vigorous", 9, 40},
	}

	fitness := 1.0
	if age := ageYears(m); age > 0 {
		fitness = math.Max(0.55, 1.25-age/100)
	}

	series := make([]Series, len(bands))
	for b, band := range bands {
		values := make([]float64, len(weekdays))
		for i := range weekdays {
			v := (band.base + vary(seed, band.slot+i)*band.base*0.45) * fitness
			values[i] = math.Round(math.Max(v, 0))
		}
		series[b] = Series{Key: band.key, Label: band.label, Values: values}
	}

	return Chart{
		ID:         IDActiveMinutes,
		Title:      "Active minutes by intensity",
		Type:       TypeGroupedBar,
		Categories: weekdays,
		Series:     series,
	}
}
