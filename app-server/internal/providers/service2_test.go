package providers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
	"github.com/stretchr/testify/require"
)

func measurementsWithDOB() domain.Measurements {
	dob := time.Unix(1615876858, 0)
	return domain.Measurements{HeightCm: 184, WeightKg: 84, BirthDate: &dob}
}

func TestService2_ConvertsUnitsAndSendsBirthDate(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Measurements struct {
				Mass   float64 `json:"mass"`
				Height float64 `json:"height"`
			} `json:"measurements"`
			BirthDate    int64  `json:"birth_date"`
			SessionToken string `json:"session_token"`
		}
		require.NoError(t, json.NewDecoder(r.Body).Decode(&body))
		require.InDelta(t, 185.188, body.Measurements.Mass, 0.01, "kg must convert to pounds")
		require.InDelta(t, 6.036, body.Measurements.Height, 0.001, "cm must convert to feet")
		require.Equal(t, int64(1615876858), body.BirthDate)
		require.NotEmpty(t, body.SessionToken)
		// Real shape: Lambda proxy envelope; the inner success payload is a
		// BARE ARRAY, not the brief's claimed {"recommendations": [...]}.
		w.Write([]byte(`{"statusCode":200,"body":"[{\"priority\": 750, \"title\": \"Have more workouts per day\", \"details\": \"Workouts help.\"}]"}`))
	}))
	defer srv.Close()

	got, err := NewService2("service2", srv.URL).Fetch(context.Background(), measurementsWithDOB())

	require.NoError(t, err)
	require.Len(t, got, 1)
	require.Equal(t, "Have more workouts per day", got[0].Title)
	require.Equal(t, "Workouts help.", got[0].Details)
	require.Equal(t, 750.0, got[0].RawScore)
	require.InDelta(t, 0.75, got[0].NormScore, 0.0001, "priority 1..1000 normalises to 0..1")
}

func TestService2_SendsFreshTokenPerRequest(t *testing.T) {
	seen := make(chan string, 2)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			SessionToken string `json:"session_token"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		seen <- body.SessionToken
		w.Write([]byte(`{"statusCode":200,"body":"[]"}`))
	}))
	defer srv.Close()

	p := NewService2("service2", srv.URL)
	_, _ = p.Fetch(context.Background(), measurementsWithDOB())
	_, _ = p.Fetch(context.Background(), measurementsWithDOB())

	first, second := <-seen, <-seen
	require.NotEqual(t, first, second, "each request must carry a unique GUID")
}

func TestService2_ParsesProviderErrorEnvelope(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		// Real shape for service2 (confirmed live): the SAME outer Lambda
		// envelope as success ("statusCode" + "body"), with errorCode/
		// errorMessage nested a level deeper, inside the "body" JSON
		// string. Unlike service1, service2 never puts errorCode at the
		// outer level.
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"statusCode":200,"body":"{\"errorCode\": 13, \"errorMessage\": \"Invalid user data\", \"statusCode\": 400}"}`))
	}))
	defer srv.Close()

	_, err := NewService2("service2", srv.URL).Fetch(context.Background(), measurementsWithDOB())

	require.Error(t, err)
	var pe *domain.ProviderError
	require.True(t, errors.As(err, &pe))
	require.Equal(t, 13, pe.Code)
	require.Equal(t, "Invalid user data", pe.Message)
	require.Equal(t, domain.KindInvalidInput, pe.Kind)
}

func TestService2_ClassifiesInvalidTokenAsAuthNotMemoryPressure(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"statusCode":200,"body":"{\"errorCode\": 39, \"errorMessage\": \"Key words file is faulty\", \"statusCode\": 503}"}`))
	}))
	defer srv.Close()

	_, err := NewService2("service2", srv.URL).Fetch(context.Background(), measurementsWithDOB())

	require.Error(t, err)
	var pe *domain.ProviderError
	require.True(t, errors.As(err, &pe))
	require.Equal(t, 39, pe.Code)
	require.Equal(t, domain.KindAuth, pe.Kind,
		"errorCode 39 is a known auth failure regardless of message wording")
}

// TestService2_ParsesRealVendorErrorEnvelope uses the literal payload
// captured live from ".../services/service2" (roughly 1 call in 3 returns
// this). Before the fix, unwrapEnvelope only ever probed the OUTER object
// for "errorCode", which service2 never sets there — the outer object only
// ever carries "statusCode" and "body" — so this response fell through to
// the success branch and json.Unmarshal into []service2Item failed with
// "cannot unmarshal object into Go value of type []providers.service2Item",
// losing the vendor's real errorCode/errorMessage and never reaching
// classifyProviderError.
func TestService2_ParsesRealVendorErrorEnvelope(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"statusCode":501,"body":"{\"errorCode\": 23, \"errorMessage\": \"Network registration running elsewhere or vice-versa\", \"statusCode\": 503}"}`))
	}))
	defer srv.Close()

	_, err := NewService2("service2", srv.URL).Fetch(context.Background(), measurementsWithDOB())

	require.Error(t, err)
	var pe *domain.ProviderError
	require.True(t, errors.As(err, &pe), "must decode into a ProviderError, not a generic decode error")
	require.Equal(t, 23, pe.Code)
	require.Equal(t, "Network registration running elsewhere or vice-versa", pe.Message)
	require.Equal(t, domain.KindTransient, pe.Kind,
		"nested statusCode 503 must classify as transient, via classifyProviderError")
}

// TestService2_ParsesRealVendorSuccessEnvelope uses the literal success
// payload captured live, to guard the ordinary path against regressions
// introduced while adding the nested-error detection above.
func TestService2_ParsesRealVendorSuccessEnvelope(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(`{"statusCode":200,"body":"[{\"priority\": 327, \"title\": \"Don't eat carbs!\", \"details\": \"Carbs are bad, mmkay.\"}]"}`))
	}))
	defer srv.Close()

	got, err := NewService2("service2", srv.URL).Fetch(context.Background(), measurementsWithDOB())

	require.NoError(t, err)
	require.Len(t, got, 1)
	require.Equal(t, "Don't eat carbs!", got[0].Title)
	require.Equal(t, "Carbs are bad, mmkay.", got[0].Details)
	require.Equal(t, 327.0, got[0].RawScore)
}

func TestService2_ParsesFastAPIValidationError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusUnprocessableEntity)
		w.Write([]byte(`{"detail":[{"loc":["body","birth_date"],"msg":"field required","type":"value_error.missing"}]}`))
	}))
	defer srv.Close()

	_, err := NewService2("service2", srv.URL).Fetch(context.Background(), measurementsWithDOB())

	require.Error(t, err)
	var pe *domain.ProviderError
	require.True(t, errors.As(err, &pe))
	require.Equal(t, domain.KindInvalidInput, pe.Kind)
	require.Contains(t, pe.Message, "birth_date")
}

func TestService2_RejectsMalformedBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(`not json at all`))
	}))
	defer srv.Close()

	_, err := NewService2("service2", srv.URL).Fetch(context.Background(), measurementsWithDOB())
	require.Error(t, err)
}

func TestService2_ClampsAboveRangePriority(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		// Documented range is 1..1000; this vendor is known to return
		// non-deterministic data, so a value above range must be clamped
		// rather than trusted, or it would dominate the merged ranking.
		w.Write([]byte(`{"statusCode":200,"body":"[{\"priority\": 4000, \"title\": \"Walk more\", \"details\": \"\"}]"}`))
	}))
	defer srv.Close()

	got, err := NewService2("service2", srv.URL).Fetch(context.Background(), measurementsWithDOB())

	require.NoError(t, err)
	require.Len(t, got, 1)
	require.Equal(t, 4000.0, got[0].RawScore, "raw score is preserved for visibility")
	require.Equal(t, 1.0, got[0].NormScore, "norm score must be clamped to the documented 0..1 range")
}

func TestService2_ClampsNegativePriority(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(`{"statusCode":200,"body":"[{\"priority\": -250, \"title\": \"Walk more\", \"details\": \"\"}]"}`))
	}))
	defer srv.Close()

	got, err := NewService2("service2", srv.URL).Fetch(context.Background(), measurementsWithDOB())

	require.NoError(t, err)
	require.Len(t, got, 1)
	require.Equal(t, -250.0, got[0].RawScore)
	require.Equal(t, 0.0, got[0].NormScore, "a negative score must be clamped to 0, not allowed to invert ranking")
}

func TestService2_RequiresBirthDate(t *testing.T) {
	req := NewService2("service2", "http://unused").Requires()
	require.False(t, req.SatisfiedBy(domain.Measurements{HeightCm: 184, WeightKg: 84}),
		"Service 2 must be skipped when no birth date is supplied")
	require.True(t, req.SatisfiedBy(measurementsWithDOB()))
}
