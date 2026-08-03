package domain

import "fmt"

// ErrorKind classifies a provider failure. Only KindTransient is worth
// retrying — that distinction is the answer when the customer asks for
// retry during live coding.
type ErrorKind string

const (
	KindInvalidInput ErrorKind = "invalid_input"
	KindTransient    ErrorKind = "transient"
	KindAuth         ErrorKind = "auth"
	KindUnknown      ErrorKind = "unknown"
)

// ProviderError normalises the two providers' incompatible error envelopes
// into one shape. It never crosses the wire as-is; the aggregator surfaces
// it as a ProviderStatus entry.
type ProviderError struct {
	Provider string
	Code     int
	Message  string
	Kind     ErrorKind
}

func (e *ProviderError) Error() string {
	return fmt.Sprintf("%s: [%d] %s (%s)", e.Provider, e.Code, e.Message, e.Kind)
}
