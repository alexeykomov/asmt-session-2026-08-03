# TLS repoint task — report

Both mobile clients now treat TLS as a first-class setting that moves
together with the host, default to the live TLS edge, and were verified
end-to-end against it. A previously-missing unit test target for
`FWAProviderStatusPresentation` was also added.

## Commits

- `debdd0b` — feat(ios): make TLS a first-class setting alongside host
- `dae2cc0` — feat(android): make TLS a first-class BuildConfig setting alongside host
- `4ef6fa7` — test(ios): add FunWithActivityCoreTests target for provider-status branch order

## Edge verification (shell, before touching client code)

```
$ grpcurl ${GRPC_HOST} list
funwithactivity.recommendations.v1.RecommendationsService
grpc.health.v1.Health
grpc.reflection.v1.ServerReflection
grpc.reflection.v1alpha.ServerReflection
```

Succeeded with **no** `-insecure`/`-plaintext` flag — confirms the edge
presents a certificate grpcurl trusts out of the box (real Let's Encrypt
cert, publicly trusted CA), consistent with "no ATS exception, no Android
network-security-config change needed."

```
$ grpcurl -d '{"measurements":{"height_cm":175,"weight_kg":70,"birth_date_unix":631152000}}' \
    ${GRPC_HOST} funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations
```
Returns all 6 canned items (3 from `service1-stub`, 3 from `service2-stub`)
when birth date is supplied; only the 3 `service1-stub` items plus a
`service2-stub` `skipped` status when it's withheld — this is the case
used for the on-device verification below.

## iOS

### What changed

- `apple-client/FunWithActivityCore/Networking/FWAServerConfig.h` / `.m` —
  `FWA_GRPC_HOST` default changed to `${GRPC_HOST}`; added
  `FWA_GRPC_USE_TLS` (default `1`) with an `-FWA_GRPC_USE_TLS <YES|NO>`
  `NSUserDefaults` launch-argument override, mirroring the existing
  `-FWA_GRPC_HOST` mechanism. Both header and implementation call out in
  comments that host and TLS flag are a pair and must be changed together
  — pointing the host at the plaintext local server while leaving TLS on
  (or vice versa) fails confusingly rather than cleanly.
- `FWAGRPCClient.m` — **no change needed**. It already applied transport
  choice per-call via `GRPCMutableCallOptions.transport` (set to
  `GRPCDefaultTransportImplList.core_secure` / `core_insecure` based on
  `[FWAServerConfig useTLS]`), scoped to the specific service/host via
  `serviceWithHost:callOptions:` — not a global toggle. This is the
  modern, non-deprecated gRPC-ObjC API for the pinned `gRPC-ProtoRPC
  ~> 1.76`: I confirmed `+[GRPCCall useInsecureConnectionsForHost:]` in
  `Pods/gRPC/src/objective-c/GRPCClient/GRPCCall+ChannelCredentials.h` is
  explicitly marked `@deprecated ... use GRPCCallOptions instead`, and
  `GRPCDefaultTransportImplList.core_secure`/`core_insecure` exist in
  `Pods/gRPC/src/objective-c/GRPCClient/GRPCTransport.h` for gRPC 1.76.0.
  The prior agent had already wired this up correctly; it was just gated
  behind a hardcoded `useTLS { return NO; }`.
- New unit test target `FunWithActivityCoreTests`
  (`apple-client/FunWithActivityCoreTests/FWAProviderStatusPresentationTests.m`)
  — see below.
- `apple-client/generate_project.rb` — adds the `FunWithActivityCoreTests`
  logic-only XCTest bundle target (depends on `FunWithActivityCore`,
  `-ObjC` linked, `GENERATE_INFOPLIST_FILE=YES`), and writes an explicit
  shared Xcode scheme (`Xcodeproj::XCScheme`) with both the app and the
  test target wired into the Test action. This was necessary:
  `xcodebuild -scheme FunWithActivity ... test` failed with "Scheme
  FunWithActivity is not currently configured for the test action" until
  a real scheme file existed — `xcodeproj`-generated projects don't get
  the auto-created schemes Xcode's GUI provides.
- `apple-client/Podfile` — added a `FunWithActivityCoreTests` target with
  the full `shared_pods` set (not just `Protobuf`), because `-ObjC`
  force-loads every Objective-C class in `FunWithActivityCore` including
  the networking classes, which need gRPC-ProtoRPC symbols at link time
  even though the tests only exercise `FWAProviderStatusPresentation`.

### Unit test — `FWAProviderStatusPresentationTests`

Three cases, matching the brief exactly:
- `testOkStatusProducesNoPresentation` — `ok=true` → no banner.
- `testSkippedStatusWithErrorTextRendersAsInfoNotDegraded` — `ok=false,
  skipped=true`, **with `error` also populated** (as the wire format
  actually sends it) → must render `FWAProviderStatusSeverityInfo`, not
  Degraded.
- `testGenuineFailureRendersAsDegraded` — `ok=false, skipped=false` →
  `FWAProviderStatusSeverityDegraded`.

**Confirmed the middle case actually catches the regression.** I
temporarily reversed the branch order in
`FWAProviderStatusPresentation.m` (checking `status.error.length > 0`
before `status.skipped`) and reran just that target:

```
$ xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' \
    -only-testing:FunWithActivityCoreTests test
...
Test Case '-[FWAProviderStatusPresentationTests testGenuineFailureRendersAsDegraded]' passed (0.005 seconds).
Test Case '-[FWAProviderStatusPresentationTests testOkStatusProducesNoPresentation]' passed (0.001 seconds).
Test Case '-[FWAProviderStatusPresentationTests testSkippedStatusWithErrorTextRendersAsInfoNotDegraded]' started.
.../FWAProviderStatusPresentationTests.m:62: error: -[FWAProviderStatusPresentationTests testSkippedStatusWithErrorTextRendersAsInfoNotDegraded] : ((presentation.severity) equal to (FWAProviderStatusSeverityInfo)) failed: ("2") is not equal to ("1")
.../FWAProviderStatusPresentationTests.m:63: error: ... [presentation.message containsString:@"skipped"] ... failed
Test Case '-[FWAProviderStatusPresentationTests testSkippedStatusWithErrorTextRendersAsInfoNotDegraded]' failed (0.056 seconds).
** TEST FAILED **
```

Reverted the reversal (file matches `git diff` clean against the
committed version), reran, all 3 tests pass:

```
Test Suite 'All tests' passed at 2026-08-03 01:36:04.441.
** TEST SUCCEEDED **
```

### Build verification

```
$ cd apple-client && pod install
...
Pod installation complete! There are 2 dependencies from the Podfile and 7 total pods installed.

$ xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build
...
** BUILD SUCCEEDED **
```

`OS=17.5` pinned (matches the prior agent's report) — this Xcode
install's default/"latest" runtime has no bare "iPhone 15" device;
`iPhone 15` only exists on the 17.5 runtime.

### On-device verification against the live TLS edge

Used the existing `DEBUG`-only launch-argument hook
(`-FWA_AUTOSUBMIT_DEMO 1`, in `FWAMeasurementViewController.m`) plus
`-FWA_GRPC_HOST`/`-FWA_GRPC_USE_TLS` launch args, as previously used for
manual on-device verification:

```
$ xcrun simctl install <iPhone 15/17.5 device udid> .../FunWithActivity.app
$ xcrun simctl spawn <udid> log stream \
    --predicate 'subsystem == "com.funwithactivity.ios"' --style compact &
$ xcrun simctl launch <udid> com.funwithactivity.ios \
    -FWA_GRPC_HOST ${GRPC_HOST} -FWA_GRPC_USE_TLS YES -FWA_AUTOSUBMIT_DEMO 1
```

Captured log output:
```
2026-08-03 01:37:51.106 [com.funwithactivity.ios:network] GetRecommendations starting — host=${GRPC_HOST} heightCm=175.0 weightKg=70.0 hasBirthDate=0
2026-08-03 01:37:51.288 [com.funwithactivity.ios:network] GetRecommendations closed — hasResponse=1 error=(null)
```

Real response over TLS (`hasResponse=1 error=(null)`, host is the sslip.io
edge — no override to plaintext, no ATS exception in `Info.plist` was
needed or added). Screenshot of the rendered Results screen:

- **NOTICES**: "service2-stub skipped — required measurements not
  supplied", info icon, informational (not error) styling — confirms the
  skipped-before-error branch renders correctly end to end, not just in
  the unit test.
- **RECOMMENDATIONS**: `Drink more water` (service1-stub, score 0.90),
  `Improve your sleep schedule` (service1-stub, score 0.65), `Walk more`
  (service1-stub, score 0.40).

## Android

### What changed

- `android-client/app/build.gradle` — added a `serverTls` Gradle property
  → `BuildConfig.SERVER_TLS` boolean (default `true`), alongside the
  existing `serverHost` → `BuildConfig.SERVER_HOST` (default changed to
  `${GRPC_HOST}`). Both the `defaultConfig` and `debug`
  buildType comments now describe them as a pair, with the actual demo
  override example: `-PserverHost=10.0.2.2:51100 -PserverTls=false`.
- `android-client/app/src/main/java/.../core/network/GrpcClient.java` —
  constructor now takes `(String serverHost, boolean useTls)` and branches
  `ManagedChannelBuilder.useTransportSecurity()` vs `.usePlaintext()`
  (grpc-okhttp transport, confirmed via `io.grpc:grpc-okhttp:1.56.0` in
  `build.gradle`).
- `FunWithActivityApplication.java` — passes `BuildConfig.SERVER_TLS`
  through to `GrpcClient`.
- `AndroidManifest.xml` / `network_security_config.xml` — **not touched**,
  as instructed. The existing debug-only cleartext allowance (already in
  place, release forbids cleartext entirely) already covers the
  documented plaintext-local-server alternative; nothing new was needed
  for the publicly-trusted TLS edge.

### Build verification

```
$ cd android-client && ./gradlew clean assembleDebug
...
BUILD SUCCESSFUL in 2s
39 actionable tasks: 37 executed, 2 up-to-date
```

Confirmed compiled defaults in the generated `BuildConfig.java`:
```java
public static final String SERVER_HOST = "${GRPC_HOST}";
public static final boolean SERVER_TLS = true;
```

### On-device verification against the live TLS edge

Installed on `Medium_Phone_API_31_2` (booted fresh, no snapshot), launched
the default build (TLS edge, no property overrides needed since it's now
the default), filled in Height=175 / Weight=70 via `adb shell input`
(birth date left "Not supplied", exercising the GDPR-skip path), tapped
"Get recommendations". Rendered result:

- Header line: "service1-stub: 3 recommendation(s) in 0 ms"
- Notice banner (light-blue, informational styling): "service2-stub
  skipped — required measurements not supplied"
- Recommendations: **Drink more water** (service1-stub, score 0.90),
  **Improve your sleep schedule** (service1-stub, score 0.65), **Walk
  more** (service1-stub, score 0.40)

`adb logcat` showed no exceptions (no `StatusRuntimeException`, no
cleartext-blocked errors) around the request — clean TLS round trip.

Matches the iOS client's rendering exactly for the same input, both
against the real edge.

## Concerns

- The `service2-stub` (3 additional items, requires birth date) path was
  exercised only via `grpcurl` in this task, not through either client's
  UI — same scope as the prior agent's iOS report. Both clients' rendering
  code is symmetric/data-driven (no special-casing per provider), so this
  is low risk, but a fresh pair of eyes exercising the birth-date-supplied
  path through the UI before a live demo would close the gap.
- iOS `FWAGRPCClient`'s TLS wiring was already correct before this task
  (per-host `GRPCMutableCallOptions`, not a global toggle) — worth noting
  explicitly since the task brief implied the transport-selection code
  itself might need writing; only the `useTLS` gate and its override
  mechanism were missing.
- No equivalent Android unit test was requested or added in this task
  (only the iOS `FWAProviderStatusPresentation` test was in scope) — if
  Android has similar provider-status-rendering logic, it's still
  uncovered.
