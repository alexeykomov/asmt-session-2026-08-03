# iOS client — FunWithActivity

Status: **built and working**, not a promissory plan. The original brief
envisaged this document standing in for an unbuilt Android client; both
mobile clients now exist, so this documents what was actually built, what
was deliberately cut and why, and what's left. Written for the customer's
architect — see [`parity-matrix.md`](./parity-matrix.md) for the
cross-platform behaviour-by-behaviour comparison this document feeds into.

## Stack and conventions

- **Objective-C, UIKit, iOS 15.0+ deployment target. No Swift, no
  SwiftUI.** Confirmed: zero `.swift` files anywhere under `apple-client/`
  except third-party CocoaPods internals (`Pods/Protobuf/objectivec/*.swift`,
  not app code). `IPHONEOS_DEPLOYMENT_TARGET = 15.0` is set on every target.
- **Why**: this mirrors an existing production monorepo's (`cyberfight`)
  conventions, which this project's house style explicitly follows rather
  than reintroducing Swift/SwiftUI for a PoC that has to sit in the same
  codebase family.
- **Targets** (`apple-client/generate_project.rb`, built with the
  `xcodeproj` gem, same pattern as the reference app):
  - `FunWithActivityCore` — static library. Networking, models, HealthKit
    integration. No UIKit dependency.
  - `FunWithActivity` — the app. All UIKit screens, depends on Core.
  - `FunWithActivityCoreTests` — XCTest bundle, depends on Core only.
  - Dependencies via `Podfile`: `gRPC-ProtoRPC ~> 1.76`, `Protobuf ~> 4.28`.
- **Manual, explicit dependency injection.** No Typhoon or other
  reflection-based DI container, unlike the reference app — `AppDelegate`
  constructs `FWAGRPCClient`, `FWAHealthKitService`, and the view
  controllers directly. This project's house convention ("prefer explicit
  construction") was read as overriding what the reference app itself
  actually does.

## Transport

gRPC over TLS to the nginx edge, authenticated with a bearer token — the
same contract as any other RecommendationsService client.

- `FWAServerConfig.h/.m` holds three build-time constants that together
  describe **one endpoint, not three independent knobs**: `FWA_GRPC_HOST`
  (in-source default is a safe placeholder, `localhost:50051`;
  `apple-client/Config/generate-xcconfig.sh` fills in the real deployed
  edge from the repo-root `.env`'s `GRPC_HOST` — see `.env.example`),
  `FWA_GRPC_USE_TLS` (default
  `1`), `FWA_GRPC_TOKEN` (default empty — set at build time for a build
  that must authenticate against a real edge). The header is explicit that
  changing one without the other two "doesn't fail loudly, it just
  hangs/fails (or gets rejected with `Unauthenticated`) in a way that's
  confusing to debug on stage."
- All three have a `DEBUG`-only `NSUserDefaults` launch-argument override
  (`-FWA_GRPC_HOST`, `-FWA_GRPC_USE_TLS`, `-FWA_GRPC_TOKEN`) for fast
  repointing during a demo without a rebuild. **Release builds always use
  the build-time constants** — verified directly on the linked binary
  (`strings`/`nm` against the actual Release Mach-O show zero matches for
  the override keys; the same search against the Debug dylib finds all
  three, validating the method). This closes what was originally a
  security-review finding (CR-003): leaving these live in Release would
  let anything able to write app defaults on a shipped build repoint the
  connection at an attacker-controlled host, downgrade off TLS, or swap
  the credential.
- `FWAGRPCClient` selects transport per-call via
  `GRPCMutableCallOptions.transport` (`core_secure`/`core_insecure`), the
  modern non-deprecated gRPC-ObjC API for the pinned pod version — not a
  process-global toggle, so it can't leak across concurrent calls.
- The bearer token is sent as `authorization: Bearer <token>` metadata on
  every `RecommendationsService` call, matching `app-server`'s
  `authInterceptor` (`app-server/cmd/server/main.go`), which fails closed
  with `Unauthenticated` when `INTERNAL_GRPC_TOKEN` is unset unless
  `ALLOW_INSECURE_GRPC=true` is explicitly set.

### Spike 1 finding: DigitalOcean App Platform cannot proxy gRPC

This is a genuine engineering finding from early spike work, not an
architecture defect, and it belongs in the customer's hands as-is:

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

(`web-server/README.md`, `web-server/nginx-grpc.conf`.) The practical
consequence for this demo build: an nginx edge tier (TLS termination +
`grpc_pass` to `app-server`) sits in front of App Platform specifically to
give native clients a route gRPC can actually traverse; browsers go
through `web-proxy` (REST, HTTP/1.1) instead and never hit this limitation.
The edge uses a real Let's Encrypt certificate via `<ip>.sslip.io` (not
self-signed) — both iOS App Transport Security and Android's default
network security config reject self-signed certificates without a
per-app exception, so this was a hard requirement, not a nicety. Server
reflection is registered but deliberately not routed through the public
edge (it stays reachable for loopback tooling only), closing what was
CR-001/CR-002.

## Health data

`FWAHealthKitService.h/.m` reads the most recent height (`HKQuantitySample`)
and weight sample plus `dateOfBirthComponents`, all three, from HealthKit.

- `+isHealthDataAvailable` gates whether the "Prefill from Health" button
  even appears on the measurement screen.
- `-requestAuthorizationWithCompletion:` requests read access to all three
  types up front.
- `-fetchMeasurementsWithCompletion:` is designed to **never fail**: any
  value HealthKit doesn't have — because the user declined that specific
  permission (HealthKit doesn't reveal per-type grant/deny, by Apple's own
  design, so a same-shaped "empty" comes back for both "denied" and "no
  data yet") or genuinely has no data for — comes back as "unavailable"
  (height/weight `0`, birth date `nil`), never as an error. The measurement
  screen leaves that specific field blank for manual entry rather than
  surfacing anything alarming.
- Manual entry remains available for every field regardless of HealthKit
  outcome — HealthKit is strictly a convenience prefill, never a
  requirement gate.

`Info.plist` declares `NSHealthShareUsageDescription` (read access, used
for real) and `NSHealthUpdateUsageDescription` (descriptive only — the app
never writes to Health).

## What is deliberately absent

- **Fault injection**: no UI hook anywhere on this client, and this is
  intentional — see
  [`fault-injection-decision.md`](./fault-injection-decision.md) for the
  full rationale (in short: it's a presenter tool for a demo page that's
  never installed on anyone's device, and shipping a "break this backend
  provider" switch inside a binary a customer could end up holding is a
  liability the convenience doesn't justify). The wire contract still
  supports it end to end — `FWAGRPCClient`'s
  `getRecommendationsWithHeightCm:weightKg:birthDateUnix:faults:completion:`
  accepts a nullable fault dictionary matching the proto's `faults` map —
  but the only call site (`FWAMeasurementViewController.m:292`) always
  passes `faults:nil`. The client is **outcome-complete** (renders
  whatever the backend actually returns, including a genuinely faulted
  provider, correctly) without being **trigger-complete** (it cannot
  demand a fault itself).
- **CoreData offline caching**: spec'd, not built. There is no CoreData
  usage anywhere in `apple-client` — no model file, no `NSManagedObject`
  subclass, not even a stub. Every launch is a fresh network round trip.
- **The Core/UI two-library split was collapsed to one for the PoC.**
  There is no separate UI static library target — `FunWithActivityCore`
  holds networking, models, and HealthKit integration; every UIKit screen
  lives directly in the `FunWithActivity` app target. A production build
  aiming for the same modularity as the reference monorepo would want to
  split screens out into their own library target; that split was judged
  not worth the overhead for a PoC with two screens.

## Verified behaviour

- **Six-row rendering.** With a birth date supplied, both providers'
  recommendations render together, correctly interleaved by descending
  score, no truncation, no zero/blank scores — driven through the real
  network → parse → render pipeline (a `DEBUG`-only launch-argument hook
  drives this headlessly in this sandbox, since UI-automation permissions
  weren't available; the code path exercised is identical to a human tap).
- **Score formatting.** Exactly two decimal places via `%.2f`, both in the
  on-screen "source · score" label (`FWAResultsViewController.m:215`) and
  the `DEBUG` verification log (`:119`).
- **Three provider outcomes, three distinct treatments.** `ok` renders as
  a plain row. `skipped` renders with `secondaryLabelColor` text and an
  `info.circle` icon (`FWAResultsViewController.m:193–195`) — informational,
  not alarming, because a skipped provider means the user declined to
  supply required data (GDPR data-minimisation), not that anything failed.
  A genuine outage (`degraded`) renders with `systemOrangeColor` text/tint
  and an `exclamationmark.triangle` icon (`:198–201`). The classification
  itself lives in `FWAProviderStatusPresentation`'s `FWAProviderStatusSeverity`
  enum (`OK` = 0, `Info`, `Degraded`), which branches on `skipped` **before**
  `error` — its header comment states plainly: "That exact inversion has
  already caused three defects on this project."
- **That branch order is pinned by a test, not just a comment.**
  `FWAProviderStatusPresentationTests.m` (`FunWithActivityCoreTests`
  target) has three cases —
  `testOkStatusProducesNoPresentation`,
  `testSkippedStatusWithErrorTextRendersAsInfoNotDegraded`,
  `testGenuineFailureRendersAsDegraded` — and the middle one was proven to
  actually catch a regression: temporarily reversing the branch order made
  exactly that test fail, for exactly the predicted reason, while the
  other two kept passing (confirming they don't accidentally depend on
  branch order either). Reverted before committing.
- **Recommendation details render**, matching Android. A dedicated
  `FWARecommendationCell` (title / details / source·score, three stacked
  labels in a `UIStackView`) replaced the original two-slot subtitle cell
  that had no room for `details`; the details label is hidden (not just
  emptied) when a recommendation has none, so rows self-size correctly in
  both directions.
- **Release hygiene.** All `DEBUG`-only demo/verification hooks
  (`-FWA_AUTOSUBMIT_DEMO`, the results-screen `os_log` readout, and the
  three `NSUserDefaults` config overrides above) were confirmed absent
  from the actual Release binary via `strings`/`nm`, not just by reading
  the `#if DEBUG` guards — stronger than a code read, since `DEBUG` is
  simply never defined in the Release build configuration, so the guarded
  code isn't compiled in the first place, not merely dead-code-stripped
  after the fact.

**One open item worth flagging honestly**: the Release build in this
environment was only built and verified for the **iOS Simulator**
destination, to avoid needing a device distribution-signing identity that
isn't available here. The demo-hook stripping above is verified on that
build; a real device-signed Release/TestFlight build, with an actual
provisioning profile, has not been produced or verified in this
environment.
