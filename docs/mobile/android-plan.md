# Android client — FunWithActivity

Status: **built and working**, not a promissory plan. The original brief
envisaged this document standing in for an unbuilt Android client, with
iOS providing the parity target; both mobile clients now exist and both
were built to the same house conventions. This documents what was
actually built, what was deliberately cut and why, and what's left. Written
for the customer's architect — see
[`parity-matrix.md`](./parity-matrix.md) for the cross-platform
behaviour-by-behaviour comparison this document feeds into.

## Stack and conventions

- **Java, XML Views, AppCompat, API 24+ (Android 7.0) minimum. No Kotlin,
  no Jetpack Compose.** Confirmed: zero `.kt` files under
  `android-client/app/src/main`; `build.gradle` pulls in no Compose
  dependency anywhere. `minSdk 24` is set explicitly in
  `app/build.gradle` (`compileSdk`/`targetSdk` 34). UI is built with
  `androidx.appcompat:appcompat:1.6.1` + `com.google.android.material:1.9.0`
  and view binding (`viewBinding true`), not Compose.
- **Why**: same reason as iOS — this mirrors the conventions of an
  existing production monorepo this project sits alongside, and the house
  style explicitly calls for matching it rather than introducing a second
  UI paradigm for a PoC.
- **Package layout** (`app/src/main/java/com/funwithactivity/app/`):
  `core/network` (gRPC channel), `core/health` (Health Connect
  availability check), `features/measurement`, `features/recommendations`.
- **Protobuf source of truth**: the Gradle protobuf plugin points directly
  at the repo's shared `api/proto/` directory
  (`sourceSets.main.proto.srcDir '../../api/proto'`) rather than
  duplicating `recommendations.proto` inside the Android project, so the
  contract can't drift between platforms.

## Transport

gRPC over TLS to the same nginx edge iOS uses, with the same bearer-token
contract.

- `app/build.gradle` exposes three `BuildConfig` fields that together
  describe **one endpoint, not three independent knobs** — the comment in
  `defaultConfig` says so explicitly: `SERVER_HOST` (in-source default is a
  safe placeholder, `localhost:50051`; `build.gradle` loads the real
  deployed edge from the repo-root `.env`'s `GRPC_HOST` when present — see
  `.env.example`), `SERVER_TLS` (default `true`),
  `SERVER_TOKEN` (default empty). All three are Gradle properties
  (`-PserverHost=...`, `-PserverTls=...`, `-PserverToken=...`), the
  Android-appropriate equivalent of iOS's launch-argument overrides —
  Android has no `NSUserDefaults`-style runtime override mechanism, so
  these are baked in at build time instead, typically for a `debug`
  install pointed at a local `app-server`
  (`./gradlew installDebug -PserverHost=10.0.2.2:51100 -PserverTls=false
  -PserverToken=testtoken123`).
- `GrpcClient.java` branches `ManagedChannelBuilder.useTransportSecurity()`
  vs `.usePlaintext()` on `SERVER_TLS` (grpc-okhttp transport), and attaches
  `authorization: Bearer <SERVER_TOKEN>` metadata via a
  `MetadataUtils.newAttachHeadersInterceptor` on every call when a token is
  present — matching `app-server`'s `authInterceptor`
  (`app-server/cmd/server/main.go`), which fails closed with
  `Unauthenticated` when `INTERNAL_GRPC_TOKEN` is unset unless
  `ALLOW_INSECURE_GRPC=true` is explicitly set. This closes what was
  originally security-review finding CR-001/CR-002 (no gRPC auth on the
  mobile path at all).

### Spike 1 finding: DigitalOcean App Platform cannot proxy gRPC

Same finding as iOS, reproduced here because it constrains this client's
transport exactly as much:

> DigitalOcean App Platform's ingress proxies **HTTP/1.1** to containers,
> so a Go gRPC server (which speaks h2c only) is unreachable through it.
> Verified empirically — `grpcurl` returns `upstream connect error ...
> reset reason: protocol error`, and a plain `curl` to the same port
> negotiates HTTP/1.1 and times out.
>
> That is a limitation of one PaaS, not of the architecture. AWS ALB with
> a gRPC target group, GCP Cloud Run, and Azure Container Apps all speak
> HTTP/2 to targets natively. The production recommendation (AWS) is
> unaffected.

(`web-server/README.md`, `web-server/nginx-grpc.conf`.) The nginx edge in
front of App Platform is what makes this client's direct gRPC connection
possible at all; it terminates TLS with a real Let's Encrypt certificate
via `<ip>.sslip.io` — required because Android's default network security
config rejects self-signed certificates without an explicit exception, the
same constraint iOS ATS imposes. `AndroidManifest.xml`/
`network_security_config.xml` were deliberately left untouched when this
was wired up: the existing debug-only cleartext allowance already covers
the documented plaintext-local-server alternative, and release forbids
cleartext entirely, so nothing new was needed for the publicly-trusted TLS
edge.

## Health data

**Cut**, for two separate and independent reasons, both worth stating
plainly rather than glossing over:

1. `androidx.health.connect:connect-client`'s read APIs
   (`HeightRecord`/`WeightRecord`) are Kotlin `suspend` functions over
   `KClass<T>`-parameterised requests. There is no Guava
   `ListenableFuture` or otherwise plain-Java-callable surface for this in
   the current artifact (unlike, say, WorkManager). Consuming it correctly
   from pure Java means hand-rolling a `Continuation` bridge and
   reflectively constructing `KClass` instances — a real engineering task,
   and one that specifically cannot be verified without a physical device
   that has Health Connect installed *and* seeded height/weight samples,
   neither of which was available in this environment. Rather than ship
   an unverified suspend/continuation bridge, the read path was cut
   cleanly. The actual fix is a small, dedicated Kotlin bridge module — a
   call for whoever owns this codebase to make, since it's a one-file
   exception to the "no Kotlin" house rule, not a reason to abandon the
   rule generally.
2. **Independent of the language problem**: Health Connect has no
   birth-date record type at all. It models measurements
   (height/weight/etc.), not user-profile fields — so date-of-birth
   prefill is impossible from this API regardless of what language reads
   it. This is a real platform constraint, not a project limitation, and
   it means Android's measurement form will always need manual
   birth-date entry, by design, independent of anything above.

What actually shipped (`core/health/HealthConnectHelper.java`, its own
Javadoc calls this out as "PARTIALLY IMPLEMENTED, by design"):

- SDK-availability detection (`HealthConnectClient.getSdkStatus`) is real,
  wired, and Java-callable without issue — it gates whether the "Prefill
  from Health Connect" button even does anything meaningful.
- The actual read never happens. `prefill()` always calls back with
  `(null, null, <a status string>)` — either
  `R.string.health_connect_unavailable` (SDK not present/usable) or
  `R.string.health_connect_no_data` (SDK available, but nothing is read).
  Manual entry is always the outcome in this build.

## What is deliberately absent

- **Fault injection**: no UI hook, and no attempt was made to add one —
  this mirrors the iOS decision exactly; see
  [`fault-injection-decision.md`](./fault-injection-decision.md). The
  request builder documents the omission inline
  (`ResultsActivity.java:88–89`): *"Demo-only fault injection map —
  unused by this client; the server treats an absent key as 'no fault'
  per provider."* — the client is outcome-complete (renders a genuinely
  faulted provider correctly) without being trigger-complete (cannot
  demand a fault).
- **Release signing.** There is no `signingConfig` on the `release` build
  type in `app/build.gradle` — `./gradlew assembleRelease` succeeds
  (Gradle doesn't require signing to *build* an APK, only to
  install/run one), and R8's own dead-code report plus a direct
  `classes.dex` string search confirm all `DEBUG`-only demo hooks are
  correctly stripped from that output, but the resulting
  `app-release-unsigned.apk` cannot be installed or run as-is. This is a
  known, flagged gap, not an oversight discovered late — do not treat
  "Release builds" as "ready to ship" without a real signing setup added
  first.

## Verified behaviour

- **Six-row rendering.** With a birth date supplied, both providers'
  recommendations render together, correctly interleaved by descending
  score, no truncation, no zero/blank scores, `details` text present
  under the title for the three rows that carry it and absent (no gap)
  for the three that don't — driven through the real network → parse →
  render pipeline via a `BuildConfig.DEBUG`-gated auto-submit `Intent`
  extra hook (`am start --ez ... AUTOSUBMIT_DEMO true`), the closest
  Android equivalent of iOS's launch-argument hook.
- **Score formatting.** Exactly two decimal places via `strings.xml`'s
  `score_format` = `"Score: %1$.2f"`.
- **Three provider outcomes, three distinct treatments.** `ok` renders in
  a quiet, non-alarming style (green/neutral "N recommendation(s) in N
  ms"). `skipped` renders with `colorStatusSkippedBg` (`#E8F0FE`) /
  `colorStatusSkippedText` (`#1A3D8F`) — light blue, informational,
  because a skipped provider means the user declined to supply required
  data (GDPR data-minimisation), not that anything failed. A genuine
  outage (`degraded`) renders with `colorStatusErrorBg` (`#FDECEA`) /
  `colorStatusErrorText` (`#B3261E`) — visually unmistakable from the skip
  case, stacked together when both occur in the same response. The
  classification lives in `ProviderStatusPresentation`'s `Severity` enum
  (`OK`/`INFO`/`DEGRADED`), extracted out of `ResultsActivity` specifically
  so it's independently testable, and it branches on `skipped` **before**
  `!ok` — the same "three prior defects on this project" rule iOS's
  equivalent class documents.
- **That branch order is pinned by a test, not just a comment.**
  `ProviderStatusPresentationTest.java` (JVM unit test, no instrumentation
  needed) has three cases — `okStatusClassifiesAsOk`,
  `skippedStatusWithErrorTextClassifiesAsInfoNotDegraded`,
  `genuineFailureClassifiesAsDegraded` — and the middle one was proven to
  actually catch a regression: temporarily reordering the branches to
  check `!status.getOk()` first made exactly that test fail
  (`expected:<INFO> but was:<DEGRADED>`), while the other two kept
  passing. Reverted before committing, matching the iOS result exactly.
- **Recommendation details render** via `RecommendationAdapter` binding
  `item.getDetails()` to its own dedicated `TextView` per card
  (`res/layout/item_recommendation.xml`) — this was already correct on
  Android from the start; it was iOS that needed a fix to catch up (see
  the iOS plan's "Verified behaviour" section).
- **Release build correctness**, short of signing: `assembleRelease`
  succeeds, and both R8's `usage.txt` dead-code report and a direct
  `strings` search over the packaged `classes.dex` confirm the
  `DEBUG`-gated auto-submit hook (all four of its identifying strings:
  the two `Intent` extra name constants, the demo birth-date constant, and
  the method name itself) are entirely absent from the release artifact,
  while the same search against the debug APK's dex finds all of them —
  validating the search methodology, not just asserting a negative.
