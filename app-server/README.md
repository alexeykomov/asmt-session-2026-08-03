# app-server

The Go gRPC service. It fans out to third-party recommendation providers,
merges what comes back, and returns a ranked set together with per-provider
status.

Roughly 1,600 lines across 19 files, with 11 test files. Small on purpose:
the interesting parts are the boundaries, not the volume.

## Request path

```
gRPC in ──► grpcservice ──► aggregator ──► providers ──► vendor HTTP
                                │           (parallel fan-out)
                                ├── Requires() gate      ← data minimisation
                                ├── per-provider timeout
                                ├── per-provider panic recovery
                                ▼
                            dedupe ──► rank ──► response
                                              (recommendations + statuses)
```

The response always carries **both** the recommendations and a per-provider
status. A caller can therefore tell the difference between "no results
because a provider failed" and "no results because a provider was
deliberately not called" — a distinction the clients render differently and
which the rest of this document keeps coming back to.

## Packages

| Package | Responsibility |
|---|---|
| `cmd/server` | wiring and configuration; no logic |
| `internal/domain` | canonical model — `Measurements`, `Recommendation`, `ProviderError` |
| `internal/providers` | one adapter per vendor, plus the registry, fault decorator and shared HTTP client |
| `internal/aggregator` | parallel fan-out, the `Requires()` gate, per-provider isolation |
| `internal/ranking` | normalisation, per-provider weighting, deduplication |
| `internal/grpcservice` | proto ⇄ domain mapping and the auth interceptor |
| `internal/analytics` | structured events, deliberately separate from the PHI path |
| `internal/faults` | demo-only fault injection |

Everything converts **into** `domain` at the adapter boundary. Service 1
speaks centimetres and kilograms, Service 2 speaks feet and pounds; that
conversion belongs in each adapter, never in the core.

## The Provider interface

This is the extension seam, and it is four methods:

```go
type Provider interface {
    Name() string
    Requires() domain.FieldSet
    Fetch(ctx context.Context, m domain.Measurements) ([]domain.Recommendation, error)
    BaseURL() string
}
```

Adding a provider is one file, one registry line, and a table test. See
`docs/integrations/_template.md`.

It is worth being explicit that a new provider is **always code, never
configuration**. The customer has confirmed they have limited or no control
over the APIs their third-party services and devices expose, so there is no
future in which providers converge on an interface we define. The two we
already have differ in request shape, item schema **and** error envelope.

## `Requires()` — data minimisation as a routing rule

`Requires()` declares which measurement fields a provider needs. The
aggregator **skips** providers whose requirements are unmet rather than
calling them with placeholder data.

That is GDPR Article 5(1)(c) expressed as code rather than as a policy
document. Withhold your birth date and Service 2 is not called at all —
reported as `skipped`, not `failed`, and rendered informationally by every
client.

The three provider outcomes are therefore distinct and must stay that way:

| Outcome | Meaning |
|---|---|
| `ok` | called, returned results |
| `skipped` | **not called** — required data was not supplied |
| `degraded` | called, failed |

A skipped status also populates `error` with an explanation. **Any code
reading these must test `skipped` before `error`.** Checking `error` first
reports a deliberate privacy decision as an outage; that inversion has
caused four separate defects in this project, and all three clients now pin
the ordering with tests.

## Concurrency, and why not `errgroup`

The fan-out uses `sync.WaitGroup`, deliberately not `errgroup`.

`errgroup` cancels sibling goroutines on the first error. Here, partial
results *are* the product — one vendor failing must not disturb another's
in-flight call. Each provider goroutine gets:

- its own `context.WithTimeout`, so one slow vendor cannot hold the response
- its own panic recovery, so a bad adapter cannot take the process down
- its own status entry, whatever happens

## Ranking and deduplication

`WeightedNormalizedRanker` normalises each provider's score onto a common
0..1 axis, then applies per-provider weights (`RANKER_WEIGHTS`). Normalising
first is what makes "confidence 0.9" and "priority 900" comparable at all.

`ExactTitleDeduper` collapses repeated titles, both within one provider's
response and across providers. When it merges, it keeps the highest-scoring
instance but carries across any `Details` the winner lacks, and records
**every** contributing provider in `Source` — so a tip both vendors returned
displays as `service1, service2`.

Because `Source` became display text, ranking weight keys off a separate
`PrimarySource` field holding the winner's single provider. Without that
split, a merged record matches no weight key and silently falls back to 1.0.

## Configuration

All from the environment; nothing is baked in. See `.env.example`.

| Variable | Purpose |
|---|---|
| `PROVIDER1_URL`, `PROVIDER2_URL` | vendor endpoints |
| `INTERNAL_GRPC_TOKEN` | shared bearer token; **fails closed** when unset |
| `ALLOW_INSECURE_GRPC` | explicit opt-out for local runs only |
| `PROVIDER_TIMEOUT_MS` | per-provider deadline (default 2000) |
| `RANKER_WEIGHTS` | e.g. `service1=1.0,service2=0.3` |
| `USE_STUB_PROVIDERS` | canned data; stubs name themselves `-stub` so fabricated data can never be mistaken on screen for a real vendor |
| `GRPC_PORT`, `HEALTH_HTTP_PORT` | listeners |

Auth fails closed: with no `INTERNAL_GRPC_TOKEN` and no explicit
`ALLOW_INSECURE_GRPC=true`, every non-health RPC is rejected. An earlier
version failed *open*, which was the actual security hole.

## Running locally

```bash
set -a; . ../.env; set +a
GRPC_PORT=51200 HEALTH_HTTP_PORT=51201 ALLOW_INSECURE_GRPC=true go run ./cmd/server
```

```bash
go test ./...
```

`api/gen/` is generated and git-ignored; the Dockerfile's `proto-builder`
stage produces it during an image build.

## What is deliberately not here

No database, no cache, no queue, no rate limiting beyond the edge, and no
authentication beyond a shared token.

That is a stated boundary rather than an oversight. The customer's expected
load is **500 RPS average, 2000 peak** — at which point fanning out to two
third-party providers on the request path means 4,000 outbound calls per
second to APIs they cannot renegotiate, from a vendor already failing about
one call in three. Production therefore has to decouple: ingest and generate
recommendations asynchronously, cache with an explicit staleness budget, put
a circuit breaker on the vendor path, and serve reads from our own store.

The per-request fan-out here exists because the brief asked for input to be
collected in the application UI. It demonstrates the merge, ranking and
degradation logic correctly; it is not the production trigger.
