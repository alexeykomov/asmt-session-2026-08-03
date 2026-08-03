# Service 2 integration contract

Status: **confirmed against the live vendor endpoint and its OpenAPI spec.**
This document previously documented the customer's written brief as fact,
with the method and URL flagged as open assumptions. Both assumptions turned
out to be correct, but **the response envelope, and the shape of the success
payload specifically, do not match what the brief described** — see
"Response" below. This is a discrepancy between the customer's own brief and
their own deployed service, recorded here rather than quietly worked around.

## Endpoint

| | |
|---|---|
| Env var | `PROVIDER2_URL` |
| URL | `${PROVIDER2_URL}` — see `.env.example` at the repo root for where to get the real value |
| Method | `POST` — confirmed against the vendor's own OpenAPI document at `/openapi.json` |
| Content-Type | `application/json` |
| Accept | `application/json` |

Service 2 is a route (`/services/service2`) on the same FastAPI-in-front-of-
Lambda deployment as Service 1 — see `service1.md` for the shared
infrastructure note.

## Authentication

Service 2 authenticates with a **fresh session token per request**, sent in
the request body as `"session_token"`. Unlike Service 1's constant dev
token, this is a v4 GUID generated with `github.com/google/uuid` on every
call to `Fetch`. The vendor's OpenAPI description confirms the intent
(`"session_token - use unique UUID every time"`); reusing a token across
requests is not an option here.

## Request body

Service 2 speaks imperial units. The adapter converts from the canonical
metric `domain.Measurements` on every request; no conversion happens
upstream of it. Request construction was already verified against the
vendor's OpenAPI schema (`Service2Item`) and is unchanged.

```json
{
  "measurements": {
    "mass": 185.188,
    "height": 6.036
  },
  "birth_date": 1615876858,
  "session_token": "3fa85f64-5717-4562-b3fc-2c963f66afa6"
}
```

| Field | Type | Unit | Notes |
|---|---|---|---|
| `measurements.mass` | number | pounds | from `domain.Measurements.WeightKg` via `domain.KgToPounds` |
| `measurements.height` | number | feet | from `domain.Measurements.HeightCm` via `domain.CmToFeet` |
| `birth_date` | int | unix seconds, UTC | from `domain.Measurements.BirthDate`, required |
| `session_token` | string | — | fresh v4 GUID, generated per request |

Service 2 **requires** a birth date (`Requires()` returns `{FieldHeight,
FieldWeight, FieldBirthDate}`). The aggregator skips Service 2 entirely for
a user who declines to supply one; `Fetch` also carries a defensive nil
check that returns a `domain.ProviderError{Kind: domain.KindInvalidInput}`
if it is ever called without one, as a belt-and-braces guard rather than a
reachable code path.

## Response: three shapes, not two — and the success shape itself was wrong

Service 2 shares the same Lambda proxy envelope and FastAPI 422 shape as
Service 1 (see `service1.md` for the general mechanics), so HTTP status is
similarly unreliable as a discriminator. **In addition, the brief's claimed
success shape for Service 2 is simply wrong**: it documented an object,
`{"recommendations": [...]}`; the live service returns a **bare array**,
identical in structure to Service 1's. The old adapter probed for a
`"recommendations"` key that does not exist in the real response and would
have silently returned zero recommendations for every successful call.

### 1. Success — Lambda envelope, `body` is a JSON *string* containing a bare array

```json
{"statusCode":200,"body":"[{\"priority\": 23, \"title\": \"...\", \"details\": \"...\"}]"}
```

`body` must be parsed a second time as JSON. The inner payload is a **bare
array**, not `{"recommendations": [...]}`:

```json
[{"priority": 23, "title": "Have more workouts per day", "details": "Workouts help."}]
```

| Field | Type | Range | Notes |
|---|---|---|---|
| `priority` | int | 1..1000 | higher is more prioritised |
| `title` | string | — | human-readable recommendation title |
| `details` | string | — | supporting detail text |

The live service has also been observed returning the **same title more
than once** in a single response (e.g. `"Go for a physical check up"` twice
in one call), and the same title has been observed from **both** Service 1
and Service 2 in the same session (e.g. `"Go for a physical check up"`,
`"Drink more still water"`). Neither adapter dedupes on its own — see
`internal/ranking.ExactTitleDeduper`, applied by the aggregator across the
full merged, cross-provider set, keeping the highest-scoring instance of
each title.

### 2. Provider error — flat object, no `body` key, HTTP 200

```json
{"errorCode":39,"errorMessage":"Short of Memory!","statusCode":503}
```

Identical shape and quirks to Service 1's provider-error envelope (see
`service1.md`): no `"body"` key, `errorCode`/`errorMessage` at the top
level, and a `statusCode` field that is the vendor's own unreliable claim,
not the real HTTP status.

| Field | Type | Notes |
|---|---|---|
| `errorCode` | int | provider-specific error code |
| `errorMessage` | string | human-readable error message; wording is not stable |
| `statusCode` | int | vendor's own claim, not the real transport status |

**Known quirk, shared with Service 1 — and the same caveat applies:**
`errorCode 39` was first observed as an invalid-token auth failure reported
with a misleading memory-exhaustion message, and the adapter classifies on
`errorCode == 39` (never on message text). But repeated testing against
Service 1's identical error mechanism shows the vendor returns a
different, apparently random `errorCode` and message on almost every
rejected call (see `service1.md`, "Response" section, for the sample of 25
calls). Treat the `errorCode == 39` case as a documented special case that
sometimes fires, not a guaranteed catch-all for auth failures on either
service.

### 3. Schema violation — FastAPI's own HTTP 422 shape

```json
{"detail":[{"loc":["body","birth_date"],"msg":"field required","type":"value_error.missing"}]}
```

Same FastAPI validation-error shape as Service 1, produced against the
`Service2Item` schema. Arrives on a real HTTP 422.

Any body that fails to decode into a JSON object at all is treated as
malformed and surfaced as a generic error, not a `domain.ProviderError`.

## Mapping to `domain.Recommendation`

| `domain.Recommendation` field | Source |
|---|---|
| `Title` | `title` |
| `Details` | `details` |
| `Source` | provider name (as passed to `NewService2`) |
| `RawScore` | `priority`, as-is |
| `NormScore` | `priority / 1000.0` — Service 2's 1..1000 priority scale normalised onto the same 0..1 axis Service 1's confidence already uses |

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
- All Service 1 and Service 2 traffic goes through one shared, tuned
  `http.Client` (30s timeout, connection pooling), built once at package
  init rather than per call.

## Resolved / no-longer-open questions

1. **HTTP method.** Confirmed `POST` against the vendor's own OpenAPI
   document.
2. **Endpoint URL.** Confirmed above; wired as the default in
   `deploy/app-platform.yaml` and `deploy/docker-compose.yml`.
3. **Session token lifecycle.** Confirmed a v4 UUID is expected
   (`session_token - use unique UUID every time` per the vendor's own
   OpenAPI description). In manual testing the live endpoint did not
   actually reject a non-UUID string in this field, but the adapter
   continues to send a proper v4 UUID per the documented contract rather
   than relying on lax server-side validation.
4. **Unit-conversion rounding discrepancy.** Still open, and still worth
   flagging: the customer's own example payload shows **184.0 lb for 84
   kg**, whereas the exact conversion (`domain.KgToPounds`, factor
   2.2046226218) gives **185.19 lb**. Their example appears rounded; we use
   the exact constant rather than matching the rounded example. Confirm this
   is acceptable, or whether the customer expects rounding to match their
   example.

## Still open

- **Response-envelope discrepancy.** As with Service 1, the brief documented
  only an inner payload shape as the response — and got that inner shape
  wrong for Service 2 specifically (`{"recommendations": [...]}` vs. the
  real bare array). Worth flagging back to the customer's technical lead:
  their brief does not match their own deployed service, on two separate
  points for this provider.
- **Duplicate titles.** The live service returns duplicate titles within a
  single response and across both providers. This is handled by
  `ExactTitleDeduper` at the aggregation layer (see
  `internal/ranking/dedupe.go`), not inside this adapter — noted here so a
  future reader does not go looking for dedupe logic in `service2.go`.
