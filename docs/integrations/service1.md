# Service 1 integration contract

Status: **confirmed against the live vendor endpoint and its OpenAPI spec.**
This document previously documented the customer's written brief as fact,
with the method and URL flagged as open assumptions. Both assumptions turned
out to be correct, but the **response envelope in the brief does not match
what the deployed service actually returns** — see "Response" below. This is
a discrepancy between the customer's own brief and their own deployed
service, not something on our side; it is recorded here rather than quietly
worked around.

## Endpoint

| | |
|---|---|
| Env var | `PROVIDER1_URL` |
| URL | `${PROVIDER1_URL}` — see `.env.example` at the repo root for where to get the real value |
| Method | `POST` — confirmed against the vendor's own OpenAPI document at `/openapi.json` |
| Content-Type | `application/json` |
| Accept | `application/json` |

The service is a FastAPI app fronting an AWS Lambda (URL shape gives it
away); Service 1 and Service 2 are two routes (`/services/service1`,
`/services/service2`) on the *same* deployment.

## Authentication

A constant session token is sent in the request body as `"token"`. The
current value baked into the adapter (`providers.NewService1`) is:

```
service1-dev
```

This matches the vendor's own OpenAPI description for the field
(`"token - use service1-dev"`), so it is not a dev-only placeholder — it is
the documented value to send in production too. Whether a different
credential is expected once real users hit this integration is still an
open question for the customer.

## Request body

Service 1 speaks metric units directly — no unit conversion happens in this
adapter. Request construction was already verified against the vendor's
OpenAPI schema (`Service1Item`) and is unchanged.

```json
{
  "height": 184.0,
  "weight": 84.0,
  "token": "service1-dev"
}
```

| Field | Type | Unit | Notes |
|---|---|---|---|
| `height` | number | centimetres | from `domain.Measurements.HeightCm`, unchanged |
| `weight` | number | kilograms | from `domain.Measurements.WeightKg`, unchanged |
| `token` | string | — | constant auth token, see above |

Service 1 does not require a birth date (`Requires()` returns
`{FieldHeight, FieldWeight}` only). A user who declines to supply a birth
date still receives Service 1 recommendations.

## Response: three shapes, not two

**The brief showed only the inner success payload — a bare array of
`{confidence, recommendation}` objects — as if that were the entire response
body.** The service actually deployed wraps every response in an AWS Lambda
proxy-integration envelope, and on top of that, schema-validation failures
take a third shape unrelated to either. HTTP status is **not** a reliable
discriminator: provider errors come back over HTTP 200 with a `statusCode`
field inside the body that itself does not match the real HTTP status. The
adapter (`unwrapEnvelope` in `envelope.go`) discriminates on the body's own
top-level JSON keys instead.

### 1. Success — Lambda envelope, `body` is a JSON *string*

```json
{"statusCode":200,"body":"[{\"confidence\": 0.34, \"recommendation\": \"Go for a physical check up\"}]"}
```

`body` must be parsed a **second time** as JSON to reach the real payload,
which is the bare array the brief described:

```json
[{"confidence": 0.34, "recommendation": "Go for a physical check up"}]
```

| Field | Type | Range | Notes |
|---|---|---|---|
| `confidence` | number | 0..1 | already normalised |
| `recommendation` | string | — | human-readable recommendation text |

The live service has also been observed returning the **same title more
than once** in a single response (e.g. `"Don't eat carbs!"` three times in
one call). The adapter does not dedupe by itself — see
`internal/ranking.ExactTitleDeduper`, applied by the aggregator across the
merged, cross-provider set.

### 2. Provider error — flat object, no `body` key, HTTP 200

```json
{"errorCode":39,"errorMessage":"Short of Memory!","statusCode":503}
```

There is no `"body"` field in this shape at all — `errorCode` and
`errorMessage` sit at the top level, alongside a `statusCode` that is the
vendor's own internal number and **does not reflect the actual transport
HTTP status** (this example arrived over a real HTTP 200).

| Field | Type | Notes |
|---|---|---|
| `errorCode` | int | provider-specific error code |
| `errorMessage` | string | human-readable error message — wording is not stable; the same `errorCode` has been observed with different text on different calls |
| `statusCode` | int | the vendor's own claim, not the real HTTP status; used only as one input to classification, never trusted alone |

**Known quirk, and a caveat about it:** an invalid token was first observed
coming back as `errorCode 39` with a message about memory exhaustion — an
**auth failure** reported as memory pressure, not a real one. The adapter
classifies specifically on `errorCode == 39`, never on message text, per
that observation.

However, further testing found that `errorCode` is not stable for
invalid-token failures — repeated calls returned different codes rather
than a consistent one — so `errorCode` alone must not be relied on to
classify that failure type, and the gap has been flagged to the customer's
technical lead as an issue with their own error contract.

### 3. Schema violation — FastAPI's own HTTP 422 shape

```json
{"detail":[{"loc":["body","weight"],"msg":"field required","type":"value_error.missing"}]}
```

This is FastAPI's standard validation-error body, produced in front of the
vendor's own handler when the request fails the `Service1Item` schema. It
shares nothing with either shape above and arrives on a real HTTP 422.

| Field | Type | Notes |
|---|---|---|
| `detail` | array | one entry per validation failure |
| `detail[].loc` | array | JSON path to the offending field, e.g. `["body", "weight"]` |
| `detail[].msg` | string | human-readable validation message |
| `detail[].type` | string | machine error type, e.g. `value_error.missing` |

Any body that fails to decode into a JSON object at all is treated as
malformed and surfaced as a generic error, not a `domain.ProviderError`.

## Mapping to `domain.Recommendation`

Each inner array item maps 1:1 to a `domain.Recommendation`:

| `domain.Recommendation` field | Source |
|---|---|
| `Title` | `recommendation` |
| `Source` | provider name (as passed to `NewService1`) |
| `RawScore` | `confidence` |
| `NormScore` | `confidence`, **unchanged** — Service 1's confidence is already scaled 0..1, so no normalisation math is applied |

## Mapping to `domain.ProviderError`

| `domain.ProviderError` field | Source |
|---|---|
| `Provider` | provider name |
| `Code` | `errorCode` (0 for a 422 validation failure, which has no error code) |
| `Message` | `errorMessage`, or the joined `loc: msg` pairs from `detail` for a 422 |
| `Kind` | `errorCode == 39` → `auth` (known quirk, see above); else provider-error `statusCode >= 500` → `transient`; else non-zero `errorCode` → `invalid_input`; a 422 body is always `invalid_input`; otherwise `unknown` |

## Operational limits

- Response bodies are read through an 8 MiB `io.LimitReader` before decoding,
  regardless of `Content-Length`, to protect the server against a
  misbehaving or malicious upstream.
- All Service 1 (and Service 2) traffic goes through one shared, tuned
  `http.Client` (30s timeout, connection pooling), built once at package
  init rather than per call.

## Resolved / no-longer-open questions

1. **HTTP method.** Confirmed `POST` against the vendor's own OpenAPI
   document.
2. **Endpoint URL.** Confirmed above; wired as the default in
   `deploy/app-platform.yaml` and `deploy/docker-compose.yml`.
3. **Token lifecycle.** `service1-dev` is the vendor-documented value, not a
   dev-only placeholder (see "Authentication"). Whether it changes for real
   production traffic beyond this PoC is still open.

## Still open

- **Response-envelope discrepancy.** The customer's own brief documented
  only the inner payload as the response shape; the deployed service wraps
  it in a Lambda proxy envelope with two additional error forms the brief
  never mentioned. Worth flagging back to the customer's technical lead —
  their brief does not match their own deployed service.
- **Error-message wording.** Not stable across calls at all — do not build
  any customer-facing behaviour on message content.
- **Error-code stability.** Not stable across calls either, on the evidence
  above; `errorCode == 39` is a documented, deliberate special case, not a
  guarantee that all auth failures will be caught. See the caveat above.
