# Security fixes report — 2026-08-03 code review findings

Fixes for CR-001, CR-002, CR-009, CR-003 from the branch's code review (the
review record is not included in this repo; the review JSON itself was not
present in this worktree either, so these were fixed against the verdict
text quoted in the task).

Three commits, one per logical fix group, on branch
`worktree-agent-abf023075fc6e9949`:

- `383b513` — CR-001 + CR-002 (mobile gRPC auth + reflection route removal)
- `8478007` — CR-009 (fail-closed auth interceptor)
- `00133e3` — CR-003 (DEBUG-gate iOS host/TLS/token overrides)

## CR-001 + CR-002 — gRPC path had no authentication

**Fix**: iOS (`FWAServerConfig`/`FWAGRPCClient`) and Android (`GrpcClient`/
`build.gradle`/`FunWithActivityApplication`) now send `authorization: Bearer
<token>` metadata on every RecommendationsService call, with the token
sourced the same way as host/TLS (build-time constant + demo-time override,
Gradle property / `-FWA_GRPC_TOKEN` launch arg). `web-server/nginx-grpc.conf`
no longer routes either `ServerReflection` service; `web-server/README.md`
updated to say reflection is registered and auth-exempt server-side (for
loopback tooling) but has no public route.

`authInterceptor`'s health/reflection bypass was left untouched, as
instructed.

### Build/test evidence

iOS pod install:
```
$ cd apple-client && pod install
...
Pod installation complete! There are 2 dependencies from the Podfile and 7 total pods installed.
```

iOS Debug build + test (simulator iPhone 15 / iOS 17.5):
```
$ xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build
...
** BUILD SUCCEEDED **

$ xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' test
...
Test Suite 'All tests' passed at 2026-08-03 10:26:25.559.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.005 (0.007) seconds
** TEST SUCCEEDED **
```

Android build + unit tests:
```
$ cd android-client && ./gradlew assembleDebug testDebugUnitTest
...
> Task :app:testDebugUnitTest
> Task :app:packageDebug
> Task :app:assembleDebug

BUILD SUCCESSFUL in 11s
45 actionable tasks: 45 executed
```

Go build/vet/fmt/test (app-server unaffected by this commit but re-verified
after generating gitignored protobuf code with `api/proto/generate_go.sh`,
which required `go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.31.0`
and `go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.3.0` since
neither was preinstalled):
```
$ go build ./... && go vet ./... && gofmt -l . && go test ./... -race -count=2
ok  	.../app-server/internal/aggregator	...
ok  	.../app-server/internal/analytics	...
ok  	.../app-server/internal/domain	...
ok  	.../app-server/internal/grpcservice	...
ok  	.../app-server/internal/providers	...
ok  	.../app-server/internal/ranking	...
```

nginx syntax was not checked with `nginx -t` — nginx is not installed in
this environment. The diff is a straight removal of two `location` blocks
plus a comment/doc update; no directive syntax was touched.

## CR-009 — authentication failed open

**Fix**: `authInterceptor` now rejects non-health/reflection RPCs with
`Unauthenticated` when `INTERNAL_GRPC_TOKEN` is unset, unless
`ALLOW_INSECURE_GRPC=true` is explicitly set. The fail-closed path logs
`slog.Error` at startup; the opt-out path logs `slog.Warn`. Health and
reflection method prefixes remain exempt either way, so probes keep working.
`deploy/docker-compose.yml` now sets `ALLOW_INSECURE_GRPC: "true"` on
app-server instead of a hardcoded `INTERNAL_GRPC_TOKEN` dev secret.

Added `app-server/cmd/server/main_test.go` (9 test cases): valid/invalid/
missing credentials with a token configured, fail-closed with no token
(with and without credentials attached), the `ALLOW_INSECURE_GRPC` opt-out,
and the health/reflection bypass across all three token states.

### Unit test evidence
```
$ go test ./... -race -count=2
ok  	github.com/funwithactivity/funwithactivity/app-server/cmd/server	1.261s
ok  	github.com/funwithactivity/funwithactivity/app-server/internal/aggregator	1.518s
ok  	github.com/funwithactivity/funwithactivity/app-server/internal/analytics	1.586s
ok  	github.com/funwithactivity/funwithactivity/app-server/internal/domain	1.745s
?   	github.com/funwithactivity/funwithactivity/app-server/internal/faults	[no test files]
ok  	github.com/funwithactivity/funwithactivity/app-server/internal/grpcservice	2.310s
ok  	github.com/funwithactivity/funwithactivity/app-server/internal/providers	2.178s
ok  	github.com/funwithactivity/funwithactivity/app-server/internal/ranking	1.906s
```
`go build ./...`, `go vet ./...`, and `gofmt -l .` were also re-run clean
after this change (exit 0, no output from any of the three).

### End-to-end evidence

Started with a real token:
```
$ GRPC_PORT=51100 HEALTH_HTTP_PORT=51101 INTERNAL_GRPC_TOKEN=testtoken123 \
    USE_STUB_PROVIDERS=true go run ./cmd/server &
{"time":"...","level":"WARN","msg":"USE_STUB_PROVIDERS=true: serving canned recommendations, not live vendor data",...}
{"time":"...","level":"INFO","msg":"grpc server starting",...,"auth_enabled":true,"allow_insecure_grpc":false}
{"time":"...","level":"INFO","msg":"http health sidecar starting","port":"51101"}
```

Call without credentials:
```
$ grpcurl -plaintext -d '{"measurements":{"heightCm":184,"weightKg":84}}' \
    localhost:51100 funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations
ERROR:
  Code: Unauthenticated
  Message: invalid token
```

Call with the correct bearer token:
```
$ grpcurl -plaintext -H 'authorization: Bearer testtoken123' \
    -d '{"measurements":{"heightCm":184,"weightKg":84}}' \
    localhost:51100 funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations
{
  "recommendations": [
    {"title": "Drink more water", "source": "service1-stub", "score": 0.9},
    {"title": "Improve your sleep schedule", "source": "service1-stub", "score": 0.65},
    {"title": "Walk more", "source": "service1-stub", "score": 0.4}
  ],
  "statuses": [
    {"name": "service1-stub", "ok": true, "count": 3},
    {"name": "service2-stub", "skipped": true, "error": "required measurements not supplied"}
  ]
}
```

No token, no opt-out — server starts but refuses non-health RPCs:
```
$ GRPC_PORT=51100 HEALTH_HTTP_PORT=51101 USE_STUB_PROVIDERS=true go run ./cmd/server &
{"time":"...","level":"ERROR","msg":"INTERNAL_GRPC_TOKEN is unset; refusing to serve non-health/reflection RPCs. Set INTERNAL_GRPC_TOKEN, or set ALLOW_INSECURE_GRPC=true to explicitly run without auth (local development only)."}
{"time":"...","level":"INFO","msg":"grpc server starting",...,"auth_enabled":false,"allow_insecure_grpc":false}

$ grpcurl -plaintext -d '{"measurements":{"heightCm":184,"weightKg":84}}' localhost:51100 .../GetRecommendations
ERROR:
  Code: Unauthenticated
  Message: server auth misconfigured: INTERNAL_GRPC_TOKEN is unset and ALLOW_INSECURE_GRPC is not set

$ grpcurl -plaintext -H 'authorization: Bearer testtoken123' -d '...' localhost:51100 .../GetRecommendations
ERROR:
  Code: Unauthenticated
  Message: server auth misconfigured: INTERNAL_GRPC_TOKEN is unset and ALLOW_INSECURE_GRPC is not set

$ curl -s http://localhost:51101/health
{"status":"ok"}

$ grpcurl -plaintext localhost:51100 grpc.health.v1.Health/Check
{"status": "SERVING"}
```

No token, explicit opt-out — server serves everything, loudly:
```
$ GRPC_PORT=51100 HEALTH_HTTP_PORT=51101 ALLOW_INSECURE_GRPC=true USE_STUB_PROVIDERS=true go run ./cmd/server &
{"time":"...","level":"WARN","msg":"INTERNAL_GRPC_TOKEN is unset; serving all RPCs without authentication because ALLOW_INSECURE_GRPC=true. Do not use this for any customer-facing deployment."}
{"time":"...","level":"INFO","msg":"grpc server starting",...,"auth_enabled":false,"allow_insecure_grpc":true}

$ grpcurl -plaintext -d '{"measurements":{"heightCm":184,"weightKg":84}}' localhost:51100 .../GetRecommendations
{ "recommendations": [ ... ], "statuses": [ ... ] }   # succeeds, no credentials
```

Ports 3000 and 50051 were left untouched throughout; all manual servers used
51100/51101 as instructed. One leftover `server` process was found already
bound to 51100/51101 at the start of this session (a stray from a prior,
apparently interrupted, run against this same worktree) and was killed
before the first verification run so the token/no-token scenarios above
each started from a clean, known state.

## CR-003 — iOS host/TLS overrides live in Release builds

**Fix**: `FWAServerConfig`'s `NSUserDefaults` reads for `grpcHost`, `useTLS`,
and the `grpcToken` override (added in the CR-001 commit) are now wrapped in
`#if DEBUG`, matching the existing convention in
`FWAMeasurementViewController`'s autosubmit demo hook. Release builds always
fall through to the build-time constants (`FWA_GRPC_HOST` /
`FWA_GRPC_USE_TLS` / `FWA_GRPC_TOKEN`).

### Release-strip verification

Built both configurations for the simulator:
```
$ xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build
** BUILD SUCCEEDED **   # Debug

$ xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -configuration Release \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build
** BUILD SUCCEEDED **   # Release
```

Debug — positive control, keys present (FunWithActivityCore compiles
directly into the app's Debug dylib, not a separate embedded framework, in
this project layout):
```
$ strings .../Debug-iphonesimulator/FunWithActivity.app/FunWithActivity.debug.dylib \
    | grep -i "FWA_GRPC_HOST\|FWA_GRPC_USE_TLS\|FWA_GRPC_TOKEN\|FWA_AUTOSUBMIT_DEMO"
FWA_AUTOSUBMIT_DEMO
FWA_AUTOSUBMIT_DEMO_BIRTHDATE
FWA_GRPC_HOST
FWA_GRPC_USE_TLS
FWA_GRPC_TOKEN
```

Release — same three override keys, absent (grep exit code 1, no matches):
```
$ strings .../Release-iphonesimulator/FunWithActivity.app/FunWithActivity \
    | grep -i "FWA_GRPC_HOST\|FWA_GRPC_USE_TLS\|FWA_GRPC_TOKEN\|FWA_AUTOSUBMIT_DEMO"
$ echo $?
1
```

`nm` confirms the class methods themselves still exist in Release (as
expected — only the `NSUserDefaults` key lookups inside them are compiled
out, not the methods):
```
$ nm -a .../Release-iphonesimulator/FunWithActivity.app/FunWithActivity | grep -i "grpcHost\|useTLS\|grpcToken"
... t +[FWAServerConfig grpcHost]
... t +[FWAServerConfig grpcToken]
... t +[FWAServerConfig useTLS]
```

Test suite (Debug, run above under CR-001/CR-002 evidence — re-ran clean
after this change too):
```
Test Suite 'All tests' passed at 2026-08-03 10:26:25.559.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.005 (0.007) seconds
```

## Concerns / notes for the merger

- The review verdict JSON path given in the task did not exist in this
  worktree (the review record is not included in this repo). Fixed strictly
  against the finding text quoted in the task prompt; if the actual JSON has
  additional detail or different finding IDs, worth a diff before merging.
- CR-003 as literally scoped only mentions the host/TLS overrides. I also
  DEBUG-gated the `grpcToken` override introduced by the CR-001 fix, on the
  reasoning that CR-001 explicitly ties host/transport/credential together
  as "one endpoint, not independent knobs" — leaving the token override
  live in Release while host/TLS were frozen would reopen that same
  seam for the credential alone. Flagging in case the reviewer wanted CR-003
  scoped narrower.
- `deploy/docker-compose.yml` previously shipped a checked-in
  `INTERNAL_GRPC_TOKEN: "dev-token-change-in-production"` shared secret. It
  now uses `ALLOW_INSECURE_GRPC: "true"` instead, per the task's explicit
  instruction to make local dev an intentional opt-out rather than silently
  benefiting from old fail-open behavior. Functionally the docker-compose
  stack already worked (token matched on both services) before this change,
  so this is a hygiene/consistency fix, not a bugfix for that file
  specifically — worth confirming this is the intended direction, since it
  also means the compose stack no longer exercises the authenticated path
  end-to-end.
- `nginx -t` could not be run against `nginx-grpc.conf` — nginx is not
  installed in this environment. The change is a pure removal of two
  `location` blocks (plus a comment), so syntax risk is low, but this
  wasn't machine-verified.
- Generated Go protobuf code (`api/gen/go/...`) is gitignored and was not
  present at the start of this task; `go build`/`go test` for app-server
  would fail without it. Regenerated it locally via
  `api/proto/generate_go.sh` (after installing `protoc-gen-go` /
  `protoc-gen-go-grpc`) purely to run the verification commands — nothing
  under `api/gen/` was committed.
- A stray `server` process was already bound to ports 51100/51101 at the
  start of this session, left over from what looks like an earlier,
  interrupted attempt at this same task in this worktree. It was killed
  before verification; no other processes or files outside this task's
  scope were touched.
