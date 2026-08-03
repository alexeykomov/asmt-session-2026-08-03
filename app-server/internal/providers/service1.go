package providers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
)

// Service1 speaks metric units directly and authenticates with a constant
// session token.
//
// Its wire contract is the shared Lambda+FastAPI envelope described in
// envelope.go: success and provider-error bodies are both JSON objects at
// the top level (the inner success payload — a bare array of items — is a
// second, string-encoded layer inside "body"), and a third, unrelated shape
// is used for schema-validation failures. An HTTP status check alone is not
// sufficient to tell success from failure.
type Service1 struct {
	name  string
	url   string
	token string
}

func NewService1(name, url string) *Service1 {
	return &Service1{name: name, url: url, token: "service1-dev"}
}

func (p *Service1) Name() string { return p.name }

// Service 1 needs no birth date. A user who declines to supply one still
// receives these recommendations.
func (p *Service1) Requires() domain.FieldSet {
	return domain.Of(domain.FieldHeight, domain.FieldWeight)
}

type service1Request struct {
	Height float64 `json:"height"` // cm
	Weight float64 `json:"weight"` // kg
	Token  string  `json:"token"`
}

type service1Item struct {
	Confidence     float64 `json:"confidence"` // 0..1
	Recommendation string  `json:"recommendation"`
}

func (p *Service1) Fetch(ctx context.Context, m domain.Measurements) ([]domain.Recommendation, error) {
	payload, err := json.Marshal(service1Request{
		Height: m.HeightCm,
		Weight: m.WeightKg,
		Token:  p.token,
	})
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.url, bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := sharedHTTPClient.Do(req)
	if err != nil {
		return nil, &domain.ProviderError{Provider: p.name, Message: err.Error(), Kind: domain.KindTransient}
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes))
	if err != nil {
		return nil, fmt.Errorf("read body: %w", err)
	}

	inner, provErr, err := unwrapEnvelope(p.name, body)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", p.name, err)
	}
	if provErr != nil {
		return nil, provErr
	}

	var items []service1Item
	if err := json.Unmarshal(inner, &items); err != nil {
		return nil, fmt.Errorf("decode success array: %w", err)
	}
	out := make([]domain.Recommendation, 0, len(items))
	for _, it := range items {
		out = append(out, domain.Recommendation{
			Title:    it.Recommendation,
			Source:   p.name,
			RawScore: it.Confidence,
			// Documented range is 0..1, but this vendor is known to return
			// non-deterministic data, so it is not trusted blindly — clamp
			// at the adapter boundary rather than trusting confidence as-is.
			NormScore: clampNormScore(p.name, it.Confidence, it.Confidence),
		})
	}
	return out, nil
}
