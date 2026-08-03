package providers

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
)

// Both vendors sit behind the same Lambda + FastAPI deployment, but they do
// NOT share one wire contract for errors — which is NOT what the customer's
// written brief described either way. Four distinct response shapes are
// possible for a single call:
//
//  1. Success — a Lambda proxy-integration envelope whose "body" is a JSON
//     *string* that must be unmarshalled a second time to reach the real
//     payload (a bare array for both services).
//  2. Service1 provider error — a Lambda-shaped object, but with no "body"
//     key at all: errorCode/errorMessage sit at the TOP level, alongside a
//     "statusCode" that is unrelated to (and sometimes contradicts) the
//     actual HTTP status the call returned. Confirmed live against
//     service1: `{"errorCode":29,"errorMessage":"...","statusCode":503}`.
//  3. Service2 provider error — the SAME outer envelope shape as (1): the
//     outer object only ever carries "statusCode" and "body", and "body" is
//     again a JSON *string* that must be unmarshalled a second time. It is
//     only once that inner payload is parsed that errorCode/errorMessage/
//     statusCode show up (that inner "statusCode" is the vendor's own,
//     unreliable claim). Confirmed live against service2:
//     `{"statusCode":501,"body":"{\"errorCode\":23,...}"}`. Earlier
//     documentation for this function assumed service2 followed shape (2);
//     it does not, and that mistake caused every real service2 error to be
//     misparsed as a malformed success array.
//  4. Schema violation — FastAPI's own HTTP 422 validation error shape,
//     `{"detail": [...]}`, produced in front of the vendor handler and
//     sharing nothing with the Lambda envelope.
//
// HTTP status is not a reliable discriminator (provider errors arrive over
// HTTP 200), so unwrapEnvelope inspects the outer top-level keys first
// (shapes 2 and 4), then — for the remaining Lambda-envelope shape shared by
// (1) and (3) — the *inner* body's keys, to tell service2's success from its
// error.

// lambdaSuccessEnvelope is form (1) above.
type lambdaSuccessEnvelope struct {
	StatusCode int    `json:"statusCode"`
	Body       string `json:"body"`
}

// lambdaErrorEnvelope is the error payload shape, used both at the outer
// level for service1 (form 2) and, for service2, only after unmarshalling
// the outer "body" string a second time (form 3). StatusCode here is the
// vendor's own (unreliable) claim, not the transport-level HTTP status.
type lambdaErrorEnvelope struct {
	ErrorCode    int    `json:"errorCode"`
	ErrorMessage string `json:"errorMessage"`
	StatusCode   int    `json:"statusCode"`
}

// fastAPIValidationError is form (3) above.
type fastAPIValidationError struct {
	Detail []struct {
		Loc  []any  `json:"loc"`
		Msg  string `json:"msg"`
		Type string `json:"type"`
	} `json:"detail"`
}

// unwrapEnvelope discriminates the response forms described above and
// returns the raw inner payload bytes (a bare JSON array, for either
// service) on success. On any error form it returns a populated
// *domain.ProviderError instead. A non-nil `error` return means the body
// did not match any known shape at all (i.e. it is genuinely malformed).
func unwrapEnvelope(providerName string, body []byte) ([]byte, *domain.ProviderError, error) {
	var probe map[string]json.RawMessage
	if err := json.Unmarshal(body, &probe); err != nil {
		return nil, nil, fmt.Errorf("decode response envelope: %w", err)
	}

	if _, isValidationError := probe["detail"]; isValidationError {
		var v fastAPIValidationError
		if err := json.Unmarshal(body, &v); err != nil {
			return nil, nil, fmt.Errorf("decode validation error: %w", err)
		}
		msgs := make([]string, 0, len(v.Detail))
		for _, d := range v.Detail {
			loc := make([]string, 0, len(d.Loc))
			for _, l := range d.Loc {
				loc = append(loc, fmt.Sprintf("%v", l))
			}
			msgs = append(msgs, fmt.Sprintf("%s: %s", strings.Join(loc, "."), d.Msg))
		}
		return nil, &domain.ProviderError{
			Provider: providerName,
			Message:  strings.Join(msgs, "; "),
			Kind:     domain.KindInvalidInput,
		}, nil
	}

	// Form (2): service1's provider error, errorCode/errorMessage at the
	// outer level, no "body" key at all.
	if _, isProviderError := probe["errorCode"]; isProviderError {
		var e lambdaErrorEnvelope
		if err := json.Unmarshal(body, &e); err != nil {
			return nil, nil, fmt.Errorf("decode provider error envelope: %w", err)
		}
		return nil, &domain.ProviderError{
			Provider: providerName,
			Code:     e.ErrorCode,
			Message:  e.ErrorMessage,
			Kind:     classifyProviderError(e.StatusCode, e.ErrorCode),
		}, nil
	}

	// Forms (1) and (3) both wrap their real payload as a JSON string under
	// "body". Which one it is can only be told apart by unmarshalling that
	// inner string a second time and probing it: service2's error shape
	// (3) is an object carrying its own nested "errorCode"; its success
	// shape (1) is a bare array.
	if _, hasBody := probe["body"]; hasBody {
		var s lambdaSuccessEnvelope
		if err := json.Unmarshal(body, &s); err != nil {
			return nil, nil, fmt.Errorf("decode success envelope: %w", err)
		}
		inner := []byte(s.Body)

		var innerProbe map[string]json.RawMessage
		if err := json.Unmarshal(inner, &innerProbe); err == nil {
			if _, isNestedProviderError := innerProbe["errorCode"]; isNestedProviderError {
				var e lambdaErrorEnvelope
				if err := json.Unmarshal(inner, &e); err != nil {
					return nil, nil, fmt.Errorf("decode nested provider error envelope: %w", err)
				}
				return nil, &domain.ProviderError{
					Provider: providerName,
					Code:     e.ErrorCode,
					Message:  e.ErrorMessage,
					Kind:     classifyProviderError(e.StatusCode, e.ErrorCode),
				}, nil
			}
		}

		return inner, nil, nil
	}

	return nil, nil, fmt.Errorf("unrecognised response envelope from %s", providerName)
}

// classifyProviderError maps a vendor error envelope onto a retry-relevant
// ErrorKind. HTTP status is not reliable here — errors arrive over HTTP 200
// with a contradicting statusCode field inside the body — so classification
// relies only on the envelope's own fields.
func classifyProviderError(envelopeStatusCode, errorCode int) domain.ErrorKind {
	// Quirk observed against the live vendor: an invalid token comes back as
	// errorCode 39 with a message about memory exhaustion — we have seen
	// both "Short of Memory!" and "Key words file is faulty" for the same
	// code, so the wording is not stable and must NOT be pattern-matched.
	// errorCode 39 itself is the one reliable signal that this is actually
	// an auth failure, not real memory pressure — hence the manual
	// classification here instead of trusting the message text.
	if errorCode == 39 {
		return domain.KindAuth
	}
	if envelopeStatusCode >= 500 {
		return domain.KindTransient
	}
	if errorCode != 0 {
		return domain.KindInvalidInput
	}
	return domain.KindUnknown
}
