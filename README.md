# FunWithActivity

A health/activity recommendation proof of concept, built for an EPAM pre-sale
architecture assessment. It fans out a user's measurements to two independent
third-party recommendation providers, merges and deduplicates what comes
back, ranks the result, and renders it — the same backend, on **web, iOS,
and Android**.

The product is a four-tab app on all three clients:

- **Recommendations** — the ranked, merged table, fetched in the background
  and refreshed automatically when something relevant changed (a manual
  Refresh control is also available). Each row drills into a detail screen
  showing per-provider provenance and where it ranked.
- **Sources** — the two providers with live status and latency, each
  drilling into a read-only detail screen; a `+` control shows the seam for
  adding a new provider.
- **Trends** — a steps bar chart, a sleep-stage pie and a grouped bar of
  active minutes, drawn with platform primitives only: raw SVG on web,
  CoreGraphics on iOS, `Canvas` on Android. No charting library on any
  platform.
- **Profile** — height, weight, and a clearable birth date, plus a
  developer-only section of per-provider fault toggles used for demoing
  resilience.

## Architecture, in a few lines

### What is in this repo — the PoC

```
Browser ──HTTP/JSON──► web-proxy ──gRPC──► app-server ──HTTP/JSON──► provider adapters
iOS/Android ──gRPC + bearer token──► nginx edge ──gRPC (h2c)──► app-server
```

- **`app-server/`** (Go) — fans out to both providers in parallel, classifies
  each result as `ok` / `skipped` (data-minimisation gate) / `degraded`
  (timed out or errored), deduplicates and ranks the merged set, and serves
  it over gRPC.
- **`web-proxy/`** (Node/Express) — the public REST façade browsers talk to;
  the only client that goes through it, since browsers can't speak gRPC
  without a proxy.
- **`web-client/`** — Closure Library SPA, compiled ADVANCED-mode, served as
  static files by `web-proxy`.
- **`apple-client/`** — Objective-C/UIKit, talks gRPC directly to the edge.
- **`android-client/`** — Java/AppCompat, same gRPC contract as iOS.
- **`api/proto/`** — the single proto contract (`recommendations.proto`)
  every internal gRPC caller shares; `generate_all.sh` drives Go and JS
  codegen.

A full breakdown — system topology (and why mobile bypasses `web-proxy`
entirely), the request flow for one recommendation call, and the five
extension seams the architecture is built around — is in
**[`docs/architecture-diagrams.md`](docs/architecture-diagrams.md)**.

Design decisions worth reading before changing client rendering behaviour
are recorded as ADRs in `docs/decisions/`:

- [`0001-replace-not-accumulate.md`](docs/decisions/0001-replace-not-accumulate.md) — each response replaces the rendered result set; clients never accumulate results across requests.
- [`0002-property-names-never-cross-the-wire.md`](docs/decisions/0002-property-names-never-cross-the-wire.md) — why the wire format is packed positional arrays, not named JSON fields, and where plain objects are still fine.

### Where this goes in production

The topology above calls both vendors **on the request path**. That works for a
demo and cannot work in production, and the reason is arithmetic rather than
taste: the customer's stated peak is **2000 RPS**, two providers deep, over
APIs they have told us they cannot renegotiate, from vendors we have measured
failing about one call in three. That is 4,000 outbound third-party calls per
second. So the vendor call moves off the request path entirely.

```
Wearables ─┐                                    ┌─► ClickHouse #1  (PHI plane)
           ├─► durable buffer ──► ingest ───────┤
Vendor   ──┘   (Kafka/Kinesis/                  └─► refresh worker (Go, scheduled)
health APIs     Pub-Sub)                              │  Requires() gate
via inbound                                           ▼
connectors                                        provider adapters
                                                  (cache + circuit breaker)
                                                      │
                                                      ▼
Browser ──► web-proxy ─┐                          Postgres  (state: profile,
                       ├─► app-server ──────────► entitlements, stored recs)
iOS/Android ──► edge ──┘   entitlement check          │
                            (in-process)              └─► ClickHouse #2 (analytics
                                                            plane, pseudonymous)
```

What survives unchanged: the edge, `web-proxy`, the gRPC contract, the three
provider outcomes (`ok` / `skipped` / `degraded`), and the `Requires()`
data-minimisation gate. **Only the gate's trigger moves** — from an inline call
to a background refresh.

What is new: persistence, a durable ingest buffer, and a read path that serves
entirely from our own store and never calls a vendor inline. **Persistence is
not a feature to add later; it is the production read path.**

Two things on that diagram are easy to misread:

- **There are two vendor seams, pointing in opposite directions.** *Inbound
  connectors* pull user data in from third-party health APIs and normalise it
  into the same schema a device sample uses. *Outbound provider adapters* call
  recommendation services. One is a PHI data source, the other a compute
  dependency — conflating them would misstate both.
- **Two ClickHouse deployments, split by access breadth rather than volume.**
  CH #1 holds health telemetry and needs almost no human access; CH #2 holds
  pseudonymous product events and needs a wide, growing audience — analysts,
  PMs, BI. Access that broad next to data that sensitive is where grants drift,
  so the boundary is a separate account, not a separate permission.

Fully drawn, with the compliance controls mapped to the obligations they
discharge, in
**[`docs/architecture-diagrams.md`](docs/architecture-diagrams.md)** — diagram 4
and section 4a.

### How we address HIPAA and GDPR

Twelve decisions, one per standard compliance challenge, in
[`docs/architecture-diagrams.md`](docs/architecture-diagrams.md) section 4a.
The load-bearing ones:

- **Identity** — a Cognito user pool per region; we never store a credential.
- **Sessions** — our own opaque token, looked up server-side on every request,
  so revocation is immediate. Never cached.
- **Consent** — append-only events; withdrawal is a new row, never an update.
- **Erasure** — crypto-shred a per-user key, so snapshots, PITR and any
  `pg_dump` become unreadable too. Row deletion cannot reach a backup.
- **Residency** — one cell per region (US, EU), users pinned home, no
  cross-border transfer.
- **Retention** — raw samples on a short partition TTL, rollups retained.

Open, and a question for the customer: whether this is HIPAA-covered or
consumer wellness under FTC HBNR. We build to HIPAA either way.

### Erasure: why crypto-shredding rather than `DELETE`

This one is worth stating in the README because it drives the storage design
rather than following from it, and because it is the first thing an architect
asks about once ClickHouse appears on a diagram.

**ClickHouse is bad at deleting.** `MergeTree` parts are immutable, so
`ALTER TABLE … DELETE` is a *mutation* that rewrites every part containing a
matching row — and after a year, one user's samples are scattered across
nearly all of them. Lightweight `DELETE FROM` is faster to issue but only
writes a `_row_exists` mask; the bytes remain until background merges rewrite
those parts. What ClickHouse *is* good at is `DROP PARTITION`, which is
metadata-only and effectively instant. So time-based retention is cheap and
per-user erasure is expensive — exactly backwards from what GDPR Art. 17 asks
for.

**Crypto-shredding** inverts that: encrypt under a per-user key, and erase by
destroying the key. The ciphertext stays and becomes permanently unreadable.
It is a general technique, not a ClickHouse one, and it wins on four counts:

| | Row deletion | Key destruction |
|---|---|---|
| Cost | O(data) — rewrite parts, propagate to replicas | O(1) — one KMS call |
| Backups, snapshots, replicas | Untouched — the user still exists in every retained backup and every S3 version | All become unreadable at once |
| Immutable / WORM storage | Fights it — Object Lock and MergeTree parts are *deliberately* undeletable | Composes with it |
| Evidence | You assert the deletion happened | An auditable, timestamped key-deletion event |

The backups row is the real argument. Deleting a user from the live database
is easy; deleting them from every retained backup is not something you can
practically do. NIST SP 800-88 recognises cryptographic erase as a
sanitisation method, so this is not a novel position.

**The limit, stated rather than discovered:** this cannot be applied to the
measurement *values* in ClickHouse. Per-user-encrypted columns are
high-entropy, so columnar compression collapses — and the volume estimates
depend on that compression — and population-insight queries aggregate *across*
users, which is impossible under per-user keys. So the mechanism applies to
the **identity linkage, not the samples**: telemetry lands under a per-user
pseudonym, the pseudonym-to-identity mapping lives encrypted in Postgres, and
erasure destroys that mapping while partition TTL ages the orphaned rows out.

The open question that follows, and one for the customer's DPO rather than for
us to assert: health time series are notoriously re-identifiable, so whether
orphaned samples are *anonymous* under Art. 4(5) — or merely pseudonymous, and
therefore still personal data — is a determination we flag rather than make.

## The two vendor integrations

Both recommendation providers are external services this project does not
control. Their corrected wire contracts — reverse-engineered against the
live endpoints, since the documented brief and the deployed behaviour
disagree in several places — are written up in
[`docs/integrations/service1.md`](docs/integrations/service1.md) and
[`docs/integrations/service2.md`](docs/integrations/service2.md). Adding a
third provider means implementing the same adapter interface; see
[`docs/integrations/_template.md`](docs/integrations/_template.md).

## Running it locally

### Prerequisites

- Go 1.23+
- Node 18+
- `protoc` 3+ with the Go plugins (`protoc-gen-go` v1.31.0,
  `protoc-gen-go-grpc` v1.3.0) for proto codegen
- A JRE (Java 17+) on `PATH` — needed only to *build* the web client (the
  Soy-to-JS and Closure compilers are jars); never needed to run it

### Configuration

Copy `.env.example` to `.env` at the repo root and fill in real values —
vendor provider URLs, a shared gRPC bearer token, and the gRPC host the
mobile clients dial. `.env` is git-ignored and never committed; every value
in `.env.example` is a placeholder. See the comments in that file for what
each variable does and which component reads it.

### Build and run

```bash
make setup    # installs Go modules + npm deps for app-server, web-proxy, web-client
make codegen  # generates Go + JS proto stubs into api/gen/ (git-ignored)
make build    # builds the app-server binary and the web-client bundle
make dev      # docker compose up --build — app-server + web-proxy together
make test     # go test ./... + web-proxy's mocha suite + web-client's mocha suite
```

Or run the pieces individually:

```bash
cd app-server && go run ./cmd/server   # gRPC on :50051, HTTP /health on :50052
```

```bash
cd web-proxy && npm install && npm test
PORT=3000 APP_SERVER_URL=localhost:50051 npm start
```

```bash
cd web-client && npm install
npm run build   # scripts/build-css.js, scripts/compile-soy.js, then scripts/compile.js
npm run lint
```

Once `web-client/public/` exists, `web-proxy` serves it as static files — it
has no Soy/Java dependency at build or run time.

The iOS and Android clients build from `apple-client/` and `android-client/`
respectively, via their normal platform toolchains (Xcode / Gradle); both
read `GRPC_HOST` (and `INTERNAL_GRPC_TOKEN` where applicable) from the same
`.env` file at build time.

## Status

This is a proof of concept built for a graded pre-sale technical
assessment, not a production system. What's built, what's designed but not
built, and what's genuinely not done is tracked honestly in the assessment
deck (`docs/deck/funwithactivity-architecture.md`, slide 18) rather than
implied by omission here.
