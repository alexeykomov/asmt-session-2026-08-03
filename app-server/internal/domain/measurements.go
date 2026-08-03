// Package domain holds the canonical model. It imports no other package in
// this project and knows nothing about proto, HTTP, or gRPC — every other
// package may depend on it, and it depends on none of them.
package domain

import "time"

const (
	cmPerFoot     = 30.48
	poundsPerKilo = 2.2046226218
)

// Measurements is always metric. Conversion to a provider's preferred units
// happens in that provider's adapter, never here.
type Measurements struct {
	HeightCm  float64
	WeightKg  float64
	BirthDate *time.Time // nil when the user declined to supply it
}

func CmToFeet(cm float64) float64   { return cm / cmPerFoot }
func KgToPounds(kg float64) float64 { return kg * poundsPerKilo }

// Field identifies one input a provider may require.
type Field int

const (
	FieldHeight Field = iota
	FieldWeight
	FieldBirthDate
)

// FieldSet is what a provider declares through Requires(). The aggregator
// skips providers whose set is not satisfied, which turns data minimisation
// into a routing rule rather than a special case.
type FieldSet map[Field]struct{}

func Of(fields ...Field) FieldSet {
	s := make(FieldSet, len(fields))
	for _, f := range fields {
		s[f] = struct{}{}
	}
	return s
}

func (s FieldSet) SatisfiedBy(m Measurements) bool {
	for f := range s {
		switch f {
		case FieldHeight:
			if m.HeightCm <= 0 {
				return false
			}
		case FieldWeight:
			if m.WeightKg <= 0 {
				return false
			}
		case FieldBirthDate:
			if m.BirthDate == nil {
				return false
			}
		}
	}
	return true
}
