# Correctness fixes report

Fixes for the correctness findings (CR-004, CR-005, CR-010, CR-011, CR-012)
from the branch's code review (the review record is not included in this
repo). One commit per finding, all in this worktree:

- `2c04945` — CR-004: pre-1970 birth dates no longer silently dropped
- `df40e16` — CR-005: malformed JSON returns 400, not a stack trace
- `2fb0cc2` — CR-010: vendor scores clamped at the adapter boundary
- `af88d65` — CR-011: web banner renders the server-supplied skip reason
- `e7bf2cb` — CR-012: `StreamVitals` marked reserved/not-implemented

Did not touch `main.go`, the mobile clients, or `nginx-grpc.conf` — those
are owned by a concurrent security-findings fix.

## CR-004 — birth dates before 1970 silently dropped

`web-proxy/src/routes/api-routes.js`, `parseMeasurements`: `birthDateUnix`
was accepted only when `> 0`, so any date before 1970-01-01 (a negative
unix timestamp) was coerced to `0` — the proto's "not supplied" sentinel —
silently skipping Service 2. The Go side (`grpcservice/service.go:59`,
`if ts := m.GetBirthDateUnix(); ts != 0`) already handled negative values
correctly; the bug was purely in this one JS coercion.

Fix: treat any finite, non-zero value as supplied. Plausibility is
validated explicitly and separately from sign — reject values in the
future, and reject values before ~150 years pre-epoch — rather than
inferring "not supplied" from the sign of the number.

Tests added (`web-proxy/test/api-recommendations.test.js`): pre-1970 date
passed through unchanged, post-1970 date passed through unchanged,
explicit `0` still treated as not-supplied, future date rejected with 400,
absurdly-old date rejected with 400.

## CR-005 — malformed JSON leaked a stack trace

`web-proxy/src/server.js`: `express.json()` throws a `SyntaxError` on an
unparseable body; nothing caught it, and `NODE_ENV` was unset everywhere
(`web-proxy/Dockerfile`, `deploy/docker-compose.yml`,
`deploy/app-platform.yaml`), so Express's default error handler ran in
development mode and echoed the stack trace back to the client.

Fix: added explicit JSON error-handling middleware after the API router,
returning `400 {"error":"invalid_json"}` for any `SyntaxError` with a
`body` property (Express's marker for a body-parser failure), and set
`NODE_ENV=production` in the runtime Docker stage plus both deploy specs
as defense in depth.

Test added: POST truncated JSON, assert 400, assert the response contains
neither `SyntaxError` nor a `/src/server.js` path.

## CR-010 — vendor scores not clamped

`app-server/internal/providers/service1.go` used `confidence` directly as
`NormScore`; `service2.go` divided `priority` by 1000. Neither
bounds-checked, so an out-of-range or negative vendor value could dominate
or invert the merged ranking. This vendor pool is known to return
non-deterministic data and misleading error codes.

Fix: added a shared `clampNormScore(providerName, raw, normScore)` helper
in `app-server/internal/providers/provider.go` that clamps to `[0,1]` and
logs at WARN (`slog.Warn`, matching the existing `registry.go` convention)
when clamping actually changed the value, so vendor drift is visible.
Wired into both adapters; `RawScore` is left unclamped (preserved for
visibility/debugging), only `NormScore` is corrected.

Tests added: above-range and negative-value cases for both
`service1_test.go` and `service2_test.go`, asserting `RawScore` is
preserved and `NormScore` is clamped to `0.0`/`1.0`.

## CR-011 — web banner hardcoded the skip reason

`ui-soy/components/degradation-banner.soy` rendered a fixed "birth date
not supplied" string for the skipped case, while Android's
`ProviderStatusPresentation` and iOS's `FWAProviderStatusPresentation`
both surface the server-supplied `error` text
(`"required measurements not supplied"`, set in
`app-server/internal/aggregator/aggregator.go:97`). That was only correct
because birth date is currently the only optional field; the moment a
second provider has a different `Requires()` set, the hardcoded string
would state the wrong reason.

Fix: render `{$status.error}` instead of the literal string. Branch order
is unchanged — `skipped` is still checked before `ok`/`error`, per the
existing comment warning that this exact inversion has already caused
three defects on this project. Styling (`recs-banner-skipped` class) is
unchanged, so the skipped case still reads as informational, not an
outage.

Rebuilt the client bundle and confirmed it still compiles under ADVANCED:
`main.min.js 14.9 KiB`, 0 errors, 32 warnings (all pre-existing
`goog.inherits`/`goog.bind`/etc. deprecation notices, unrelated to this
change). `npm run lint` is clean.

## CR-012 — StreamVitals declared but unimplemented (decision: keep, mark)

`api/proto/recommendations.proto`: added a comment on the `StreamVitals`
rpc stating it is reserved, not yet implemented, and naming the SSE vitals
work as where streaming vitals actually lands. No implementation added, no
deletion. Regenerated Go proto code locally to confirm the comment-only
change doesn't break codegen or `go build`/`go vet` (generated code is
gitignored under `api/gen/`, so nothing to commit there).

## Verification

```
$ cd app-server && go build ./... && go vet ./... && gofmt -l .
(no output — success)

$ go test ./... -race -count=2
?   	.../app-server/cmd/server	[no test files]
ok  	.../app-server/internal/aggregator	1.374s
ok  	.../app-server/internal/analytics	1.471s
ok  	.../app-server/internal/domain	1.686s
?   	.../app-server/internal/faults	[no test files]
ok  	.../app-server/internal/grpcservice	1.315s
ok  	.../app-server/internal/providers	1.894s
ok  	.../app-server/internal/ranking	1.494s

$ cd ../web-proxy && npm test
  web-proxy /api/recommendations
    ✔ returns ranked recommendations with provider statuses
    ✔ passes measurements through to app-server
    ✔ omits birthDateUnix when the user declined to supply it
    ✔ passes through a pre-1970 birth date instead of coercing it to 0
    ✔ passes through a post-1970 birth date unchanged
    ✔ treats an explicit 0 birthDateUnix as not supplied
    ✔ rejects a future birth date with 400
    ✔ rejects an absurdly old birth date with 400
    ✔ forwards fault modes for the demo toggle
    ✔ rejects a non-numeric height with 400
    ✔ returns 502 when app-server is unreachable
    ✔ returns 400 with no stack trace for malformed JSON
    ✔ GET /health returns ok
  13 passing (92ms)

$ cd ../web-client && npm run build
main.min.js 14.9 KiB
0 error(s), 32 warning(s), 96.5% typed   (all warnings pre-existing goog.* deprecations)

$ npm run lint
(no output — clean)
```

### Live run against the real vendor endpoints

Note: `app-server/go.mod` requires the generated proto Go module
(`api/gen/go/funwithactivity/api`), which is gitignored and was not
present in this fresh worktree. Regenerated it locally with
`./api/proto/generate_go.sh` (after `go install`-ing `protoc-gen-go` and
`protoc-gen-go-grpc` at the pinned versions) before `go build`/`go run`
would succeed — this is expected/pre-existing project setup, not a defect.

```
$ cd app-server && GRPC_PORT=51100 HEALTH_HTTP_PORT=51101 \
  PROVIDER1_URL=${PROVIDER1_URL} \
  PROVIDER2_URL=${PROVIDER2_URL} \
  go run ./cmd/server &
$ cd web-proxy && PORT=51102 APP_SERVER_URL=localhost:51100 node src/server.js &
```

**Normal request** (first call hit a cold-start Lambda timeout on Service 2
at the 2s `PROVIDER_TIMEOUT_MS`; retried once and both services returned):

```
$ curl -X POST http://localhost:51102/api/recommendations \
  -H 'Content-Type: application/json' \
  -d '{"heightCm":184,"weightKg":84,"birthDateUnix":1615876858}'
HTTP 200
{"recommendations":[... 8 items from service1+service2 ...],
 "statuses":[
   {"name":"service1","ok":true,"skipped":false,"error":"","count":1,"latencyMs":1104},
   {"name":"service2","ok":true,"skipped":false,"error":"","count":15,"latencyMs":65}]}
```

**Pre-1970 birth date** — the CR-004 regression check. `birthDateUnix`
= `-157766400` (1965-01-01), a negative timestamp. Service 2 now runs
instead of being skipped:

```
$ curl -X POST http://localhost:51102/api/recommendations \
  -H 'Content-Type: application/json' \
  -d '{"heightCm":184,"weightKg":84,"birthDateUnix":-157766400}'
HTTP 200
{"recommendations":[... 7 items from service1+service2 ...],
 "statuses":[
   {"name":"service1","ok":true,"skipped":false,"error":"","count":6,"latencyMs":39},
   {"name":"service2","ok":true,"skipped":false,"error":"","count":14,"latencyMs":88}]}
```

**Omitted birth date** — Service 2 still correctly skipped, with the
server-supplied text CR-011's banner fix now renders:

```
$ curl -X POST http://localhost:51102/api/recommendations \
  -H 'Content-Type: application/json' \
  -d '{"heightCm":184,"weightKg":84}'
HTTP 200
{"recommendations":[... 5 items from service1 only ...],
 "statuses":[
   {"name":"service1","ok":true,"skipped":false,"error":"","count":7,"latencyMs":1041},
   {"name":"service2","ok":false,"skipped":true,"error":"required measurements not supplied","count":0,"latencyMs":0}]}
```

**Malformed JSON** — CR-005 regression check:

```
$ curl -X POST http://localhost:51102/api/recommendations \
  -H 'Content-Type: application/json' \
  -d '{"heightCm": 184,'
HTTP 400
{"error":"invalid_json"}
```

**Bonus spot-check** — future birth date rejected (CR-004's plausibility
guard), confirmed live:

```
$ curl -X POST http://localhost:51102/api/recommendations \
  -H 'Content-Type: application/json' \
  -d '{"heightCm":184,"weightKg":84,"birthDateUnix":9999999999}'
HTTP 400
{"error":"invalid_measurements"}
```

Both background processes were stopped after verification.

## Concerns / notes for the merge

- Service 2's Lambda cold start took long enough on the very first call to
  exceed `PROVIDER_TIMEOUT_MS=2000`, causing a transient `false`/`ok`
  status on the first "normal request" probe. This is expected per the
  task brief and not a regression — a retry succeeded immediately.
- The generated proto Go package (`api/gen/`) is gitignored and was
  missing in this fresh worktree; it had to be regenerated locally to run
  `go build`/`go run` at all. This is pre-existing project setup (documented
  in the `Makefile`'s `codegen` target), not something introduced by this
  work, but worth flagging in case CI doesn't run `make codegen` before
  `go build`.
- CR-011's fix assumes every provider's `error` field is always
  human-presentable when `skipped` is true — true today because the only
  skip path is `aggregator.go`'s fixed `"required measurements not
  supplied"` string. If a future provider populates `error` differently
  for its skip case, that text needs to stay end-user-appropriate at the
  source (aggregator), since the client now displays it verbatim on all
  three platforms.
- Did not touch `web-proxy/src/grpc-client.js`, `main.go`, the mobile
  clients, or `nginx-grpc.conf`, consistent with the concurrent
  security-findings work in those files.
