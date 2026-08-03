package providers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
	"github.com/stretchr/testify/require"
)

func TestService1_BaseURLReturnsConfiguredEndpoint(t *testing.T) {
	require.Equal(t, "https://example.test/service1",
		NewService1("service1", "https://example.test/service1").BaseURL())
}

func TestService1_ParsesArraySuccess(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		require.NoError(t, json.NewDecoder(r.Body).Decode(&body))
		require.Equal(t, 184.0, body["height"])
		require.Equal(t, 84.0, body["weight"])
		require.Equal(t, "service1-dev", body["token"])
		// Real shape: Lambda proxy envelope, "body" is a JSON string that
		// itself must be parsed a second time.
		w.Write([]byte(`{"statusCode":200,"body":"[{\"confidence\": 0.4, \"recommendation\": \"Walk more\"}, {\"confidence\": 0.9, \"recommendation\": \"Drink water\"}]"}`))
	}))
	defer srv.Close()

	got, err := NewService1("service1", srv.URL).
		Fetch(context.Background(), domain.Measurements{HeightCm: 184, WeightKg: 84})

	require.NoError(t, err)
	require.Len(t, got, 2)
	require.Equal(t, "Walk more", got[0].Title)
	require.Equal(t, 0.4, got[0].RawScore)
	require.Equal(t, 0.4, got[0].NormScore, "confidence is already 0..1")
	require.Equal(t, "service1", got[0].Source)
}

func TestService1_ParsesProviderErrorEnvelope(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		// Real shape (confirmed live against service1, unlike service2): no
		// "body" key at all, errorCode/errorMessage live at the top level,
		// and HTTP status is 200 even though this is a failure — the
		// embedded statusCode field is the vendor's own (unreliable) claim.
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"errorCode":13,"errorMessage":"Invalid user data","statusCode":400}`))
	}))
	defer srv.Close()

	_, err := NewService1("service1", srv.URL).
		Fetch(context.Background(), domain.Measurements{HeightCm: 184, WeightKg: 84})

	require.Error(t, err)
	var pe *domain.ProviderError
	require.True(t, errors.As(err, &pe))
	require.Equal(t, 13, pe.Code)
	require.Equal(t, "Invalid user data", pe.Message)
	require.Equal(t, domain.KindInvalidInput, pe.Kind)
}

// TestService1_ParsesRealVendorErrorEnvelope uses the literal payload
// captured live from service1. Unlike service2 (see
// TestService2_ParsesRealVendorErrorEnvelope), service1 puts errorCode at
// the OUTER level with no "body" wrapper, so it was already handled
// correctly by unwrapEnvelope's pre-existing top-level probe and is
// unaffected by the service2 defect. This test pins that down so a future
// unification of the two error shapes cannot silently break service1.
func TestService1_ParsesRealVendorErrorEnvelope(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"errorCode":29,"errorMessage":"No deleted lines to Zap","statusCode":503}`))
	}))
	defer srv.Close()

	_, err := NewService1("service1", srv.URL).
		Fetch(context.Background(), domain.Measurements{HeightCm: 184, WeightKg: 84})

	require.Error(t, err)
	var pe *domain.ProviderError
	require.True(t, errors.As(err, &pe))
	require.Equal(t, 29, pe.Code)
	require.Equal(t, "No deleted lines to Zap", pe.Message)
	require.Equal(t, domain.KindTransient, pe.Kind)
}

func TestService1_ClassifiesTransientProviderError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK) // real HTTP status is useless here
		w.Write([]byte(`{"errorCode":7,"errorMessage":"Upstream overloaded","statusCode":503}`))
	}))
	defer srv.Close()

	_, err := NewService1("service1", srv.URL).
		Fetch(context.Background(), domain.Measurements{HeightCm: 184, WeightKg: 84})

	require.Error(t, err)
	var pe *domain.ProviderError
	require.True(t, errors.As(err, &pe))
	require.Equal(t, domain.KindTransient, pe.Kind)
}

func TestService1_ClassifiesInvalidTokenAsAuthNotMemoryPressure(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		// Live quirk: an invalid token comes back as errorCode 39 with a
		// message about memory exhaustion, and an embedded statusCode of
		// 503 that would otherwise read as transient. Classification must
		// key off errorCode 39, not the message text or the embedded
		// statusCode.
		w.Write([]byte(`{"errorCode":39,"errorMessage":"Short of Memory!","statusCode":503}`))
	}))
	defer srv.Close()

	_, err := NewService1("service1", srv.URL).
		Fetch(context.Background(), domain.Measurements{HeightCm: 184, WeightKg: 84})

	require.Error(t, err)
	var pe *domain.ProviderError
	require.True(t, errors.As(err, &pe))
	require.Equal(t, 39, pe.Code)
	require.Equal(t, domain.KindAuth, pe.Kind, "errorCode 39 is a known auth failure, not real memory pressure")
}

func TestService1_ParsesFastAPIValidationError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		// Real shape: FastAPI's own HTTP 422 schema-validation body, wholly
		// unrelated to the Lambda envelope.
		w.WriteHeader(http.StatusUnprocessableEntity)
		w.Write([]byte(`{"detail":[{"loc":["body","weight"],"msg":"field required","type":"value_error.missing"}]}`))
	}))
	defer srv.Close()

	_, err := NewService1("service1", srv.URL).
		Fetch(context.Background(), domain.Measurements{HeightCm: 184, WeightKg: 84})

	require.Error(t, err)
	var pe *domain.ProviderError
	require.True(t, errors.As(err, &pe))
	require.Equal(t, domain.KindInvalidInput, pe.Kind)
	require.Contains(t, pe.Message, "weight")
}

func TestService1_RejectsMalformedBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(`not json at all`))
	}))
	defer srv.Close()

	_, err := NewService1("service1", srv.URL).
		Fetch(context.Background(), domain.Measurements{HeightCm: 184, WeightKg: 84})
	require.Error(t, err)
}

func TestService1_ClampsAboveRangeConfidence(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		// Documented range is 0..1; this vendor is known to return
		// non-deterministic data, so a value above range must be clamped
		// rather than trusted, or it would dominate the merged ranking.
		w.Write([]byte(`{"statusCode":200,"body":"[{\"confidence\": 1.7, \"recommendation\": \"Walk more\"}]"}`))
	}))
	defer srv.Close()

	got, err := NewService1("service1", srv.URL).
		Fetch(context.Background(), domain.Measurements{HeightCm: 184, WeightKg: 84})

	require.NoError(t, err)
	require.Len(t, got, 1)
	require.Equal(t, 1.7, got[0].RawScore, "raw score is preserved for visibility")
	require.Equal(t, 1.0, got[0].NormScore, "norm score must be clamped to the documented 0..1 range")
}

func TestService1_ClampsBelowRangeConfidence(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(`{"statusCode":200,"body":"[{\"confidence\": -0.3, \"recommendation\": \"Walk more\"}]"}`))
	}))
	defer srv.Close()

	got, err := NewService1("service1", srv.URL).
		Fetch(context.Background(), domain.Measurements{HeightCm: 184, WeightKg: 84})

	require.NoError(t, err)
	require.Len(t, got, 1)
	require.Equal(t, -0.3, got[0].RawScore)
	require.Equal(t, 0.0, got[0].NormScore, "a negative score must be clamped to 0, not allowed to invert ranking")
}

func TestService1_DoesNotRequireBirthDate(t *testing.T) {
	req := NewService1("service1", "http://unused").Requires()
	require.True(t, req.SatisfiedBy(domain.Measurements{HeightCm: 184, WeightKg: 84}),
		"Service 1 must run without a birth date")
}
