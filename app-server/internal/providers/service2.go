package providers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/google/uuid"

	"github.com/funwithactivity/funwithactivity/app-server/internal/domain"
)

// service2MaxPriority is the top of Service 2's 1..1000 priority scale.
// Normalising by it puts the score on the same 0..1 axis as Service 1's
// confidence — see ranking.WeightedNormalizedRanker for why that is a
// judgment call rather than an equivalence.
const service2MaxPriority = 1000.0

// Service2 wants imperial units, a birth date as unix seconds UTC, and a
// fresh GUID for every request.
//
// Its wire contract is the same shared Lambda+FastAPI envelope Service1
// uses (see envelope.go). The one shape difference between the two services
// is the inner success payload: both are bare arrays, not the brief's
// claimed {"recommendations": [...]} object.
type Service2 struct {
	name string
	url  string
}

func NewService2(name, url string) *Service2 {
	return &Service2{name: name, url: url}
}

func (p *Service2) Name() string { return p.name }

func (p *Service2) Requires() domain.FieldSet {
	return domain.Of(domain.FieldHeight, domain.FieldWeight, domain.FieldBirthDate)
}

type service2Measurements struct {
	Mass   float64 `json:"mass"`   // pounds
	Height float64 `json:"height"` // feet
}

type service2Request struct {
	Measurements service2Measurements `json:"measurements"`
	BirthDate    int64                `json:"birth_date"` // unix seconds, UTC
	SessionToken string               `json:"session_token"`
}

type service2Item struct {
	Priority int    `json:"priority"` // 1..1000, higher is more prioritised
	Title    string `json:"title"`
	Details  string `json:"details"`
}

func (p *Service2) Fetch(ctx context.Context, m domain.Measurements) ([]domain.Recommendation, error) {
	if m.BirthDate == nil {
		// Defensive: the aggregator's Requires() check should have skipped us.
		return nil, &domain.ProviderError{
			Provider: p.name,
			Message:  "birth date required",
			Kind:     domain.KindInvalidInput,
		}
	}

	payload, err := json.Marshal(service2Request{
		Measurements: service2Measurements{
			Mass:   domain.KgToPounds(m.WeightKg),
			Height: domain.CmToFeet(m.HeightCm),
		},
		BirthDate:    m.BirthDate.UTC().Unix(),
		SessionToken: uuid.NewString(),
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

	// Unlike the brief's claimed {"recommendations": [...]} object, the real
	// vendor's inner success payload is a bare array, same as Service 1's.
	var items []service2Item
	if err := json.Unmarshal(inner, &items); err != nil {
		return nil, fmt.Errorf("decode success array: %w", err)
	}

	out := make([]domain.Recommendation, 0, len(items))
	for _, it := range items {
		rawScore := float64(it.Priority)
		// Documented range is 1..1000, but this vendor is known to return
		// non-deterministic data, so it is not trusted blindly — clamp at
		// the adapter boundary rather than trusting the normalised value
		// derived from priority as-is.
		normScore := clampNormScore(p.name, rawScore, rawScore/service2MaxPriority)
		out = append(out, domain.Recommendation{
			Title:     it.Title,
			Details:   it.Details,
			Source:    p.name,
			RawScore:  rawScore,
			NormScore: normScore,
		})
	}
	return out, nil
}
