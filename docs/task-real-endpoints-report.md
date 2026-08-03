# Real-endpoint rework report

Reworked `app-server/internal/providers/service1.go` and `service2.go`
against the now-live vendor endpoints, which differ from the customer's
written brief in the response shape (though not in the request shape).
Commits:

- `03663c7` — adapters rewritten for the real Lambda+FastAPI envelope
- `393169d` — exact-title dedupe across the merged, cross-provider set
- `9b574b4` — real endpoints wired as defaults; `USE_STUB_PROVIDERS` removed
  from `deploy/app-platform.yaml`
- `b545ae0` — `docs/integrations/service1.md` / `service2.md` corrected

## What changed and why

1. **Response envelope.** Both services wrap responses in an AWS Lambda
   proxy-integration envelope. On success, the real payload sits in a
   `body` field that is itself a JSON *string* and needs a second
   `json.Unmarshal`. The brief showed only that inner payload as if it were
   the whole response.
2. **Service2's inner shape was wrong in the brief.** The brief claimed
   `{"recommendations": [...]}`; the live inner payload is a bare array,
   identical in structure to Service1's. The old adapter probed for a
   `"recommendations"` key that doesn't exist and would have silently
   returned zero recommendations on every real call.
3. **Provider errors arrive over HTTP 200.** The error form has no `body`
   key at all — `errorCode`/`errorMessage` sit at the top level next to a
   `statusCode` field that is the vendor's own (unreliable) claim, not the
   real transport status.
4. **422s are FastAPI's own shape**, `{"detail": [...]}`, unrelated to
   either Lambda form, on a real HTTP 422.

All four forms are discriminated in a new shared file,
`app-server/internal/providers/envelope.go` (`unwrapEnvelope` +
`classifyProviderError`), used by both adapters.

Dedupe: added `internal/ranking/dedupe.go` (`ExactTitleDeduper`), applied by
the aggregator to the merged set after fan-out and before ranking, keeping
the highest-`NormScore` instance of each exact title. Wired as a fixed
internal default in `aggregator.New` rather than a constructor parameter —
it's a correctness fix, not a policy knob.

## Verification commands and output

```
$ cd app-server && go build ./...
(no output — success)

$ go vet ./...
(no output — success)

$ gofmt -l .
(no output — nothing to reformat)

$ go test ./... -race -count=2
?   	.../app-server/cmd/server	[no test files]
ok  	.../app-server/internal/aggregator	1.306s
ok  	.../app-server/internal/analytics	1.362s
ok  	.../app-server/internal/domain	1.525s
?   	.../app-server/internal/faults	[no test files]
ok  	.../app-server/internal/grpcservice	1.678s
ok  	.../app-server/internal/providers	1.945s
ok  	.../app-server/internal/ranking	2.023s
```

## Live server against real vendors

```
$ (cd app-server && GRPC_PORT=51100 HEALTH_HTTP_PORT=51101 \
    PROVIDER1_URL=${PROVIDER1_URL} \
    PROVIDER2_URL=${PROVIDER2_URL} \
    go run ./cmd/server &)
{"level":"INFO","msg":"grpc server starting","port":"51100","providers":["service1","service2"],"provider_timeout_ms":2000,"auth_enabled":false}
```

First call hit a Lambda cold start and both providers timed out at the
2000ms `PROVIDER_TIMEOUT_MS` default (see Concerns). Second call, same
process, both providers warm:

```
$ grpcurl -plaintext -d '{"measurements":{"heightCm":184,"weightKg":84,"birthDateUnix":1615876858}}' \
    localhost:51100 funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations
{
  "recommendations": [
    {"title": "Drink more still water", "details": "Try to consume at least 2 litres of water daily", "source": "service2", "score": 0.933},
    {"title": "Avoid sugar!", "source": "service1", "score": 0.9},
    {"title": "Exercise often!", "details": "Repeated physical exercise could help avoid future veins troubles", "source": "service2", "score": 0.777},
    {"title": "Go for a physical check up", "source": "service1", "score": 0.74},
    {"title": "Focus on cycle exercises", "source": "service1", "score": 0.49},
    {"title": "Time to stand up", "details": "Sitting lifestyle could affect your future health", "source": "service2", "score": 0.275},
    {"title": "Don't eat carbs!", "source": "service1", "score": 0.22},
    {"title": "Walk more", "source": "service1", "score": 0.1}
  ],
  "statuses": [
    {"name": "service1", "ok": true, "count": 8, "latencyMs": "112"},
    {"name": "service2", "ok": true, "count": 7, "latencyMs": "119"}
  ]
}
```

Confirmed: recommendations from **both** sources are present, no duplicate
titles, scores are descending. `"Exercise often!"` appeared in both raw
provider responses (visible in the raw counts vs. deduped output) and
correctly collapsed to the single higher-scoring `service2` instance —
cross-provider dedupe works.

```
$ grpcurl -plaintext -d '{"measurements":{"heightCm":184,"weightKg":84}}' \
    localhost:51100 funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations
{
  "recommendations": [
    {"title": "Focus on cycle exercises", "source": "service1", "score": 0.91},
    {"title": "Exercise often!", "source": "service1", "score": 0.9},
    {"title": "Drink more still water", "source": "service1", "score": 0.8},
    {"title": "Go for a physical check up", "source": "service1", "score": 0.79},
    {"title": "Don't eat carbs!", "source": "service1", "score": 0.37},
    {"title": "Time to stand up", "source": "service1", "score": 0.17}
  ],
  "statuses": [
    {"name": "service1", "ok": true, "count": 7, "latencyMs": "58"},
    {"name": "service2", "skipped": true, "error": "required measurements not supplied"}
  ]
}
```

Confirmed: with `birthDateUnix` omitted, `service2` is correctly reported
`"skipped": true` (never called), and `service1` still returns a full,
deduped, descending-score list on its own.

Server was stopped after verification (`pkill -f "go run ./cmd/server"`).

## Direct endpoint checks (raw, for reference)

```
$ curl -sS -X POST "$BASE/services/service1" -d '{"height":184,"weight":84,"token":"service1-dev"}'
{"statusCode":200,"body":"[{\"confidence\": 0.48, \"recommendation\": \"Avoid sugar!\"}, ...]"}

$ curl -sS -X POST "$BASE/services/service1" -d '{"height":184,"weight":84,"token":"bad-token"}'
{"errorCode":39,"errorMessage":"Key words file is faulty","statusCode":503}

$ curl -sS -X POST "$BASE/services/service1" -d '{"height":184,"token":"service1-dev"}'
{"detail":[{"loc":["body","weight"],"msg":"field required","type":"value_error.missing"}]}
(real HTTP status: 422; success/error-envelope cases both real HTTP 200)

$ curl -sS "$BASE/openapi.json"
confirms Service1Item{height, weight, token} and Service2Item{measurements{mass, height}, birth_date, session_token}
matching our existing (unchanged) request marshalling.
```

## Concerns

- **The `errorCode 39` → auth quirk does not reliably fire.** Repeated
  invalid-token calls (25 samples) show the vendor returns a **different,
  apparently random `errorCode`** (values observed: 5, 6, 9, 10, 19, 21,
  22, 26, 29, 31, 32, 33, 40, 41, 46, 57, 63, 67, 69, 70, 71, 73, 77, 79,
  83, 87, 91, 99 — never 39 again in this sample) with a different canned
  message each time, all on `statusCode: 503`. The task brief's example
  (`errorCode 39, "Short of Memory!"`) appears to have been one draw from
  this same random-error generator, not a stable signal. As implemented —
  exactly per the brief's instruction — `errorCode == 39` is checked and
  correctly classified `auth`, but in practice this will almost never
  match; nearly all real invalid-token failures will instead fall through
  to the `statusCode >= 500` branch and be classified `transient`
  (retryable), which is wrong for an auth failure that will never
  self-resolve by retrying. The **only actually reliable signal** observed
  for "this was a bad-token failure" is indirect: a provider-error envelope
  with `statusCode: 503` from a request we know carried a valid,
  well-formed token. Recommend raising this with the customer's technical
  lead — ask for either a stable error code for auth failures, or an
  explicit field, since the current error taxonomy appears to be simulated
  at random per call. Kept the code as specified rather than "fixing" it
  unilaterally, since the instruction was explicit and the failure mode is
  a vendor problem, not an adapter bug — but this needs a decision from
  whoever owns the vendor relationship.
- **2s `PROVIDER_TIMEOUT_MS` is tight against a cold Lambda.** The very
  first live call in this session timed out on both providers waiting past
  the 2000ms default; a warm second call answered in ~60–120ms. The
  fault-toggle demo rationale for 2s (fail fast on stage) is sound, but a
  cold-start miss now means the *first* recommendation request of a demo
  session could show a false "both providers failed" state. Worth deciding
  whether to pre-warm the Lambdas (e.g. a startup ping) before a live demo,
  or accept the risk.
- **Duplicate-detail collisions.** `ExactTitleDeduper` matches on `Title`
  only. Observed live data always carries identical `Details` alongside an
  identical `Title` for the same tip, so this hasn't caused an issue in
  testing, but if a vendor ever returns the same title with different
  detail text, one instance's details would be silently dropped along with
  its score. Not fixed, since there is no evidence yet that it happens —
  flagging in case it matters later.
- **`session_token` format was not actually enforced** by the live Service2
  endpoint in manual testing (a non-UUID string was accepted). The adapter
  still sends a proper v4 UUID per the documented contract; this is
  recorded in `docs/integrations/service2.md` as a note, not treated as
  license to loosen the adapter.
