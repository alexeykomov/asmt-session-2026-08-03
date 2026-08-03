# Mobile verification report — closing the last two demo gaps

Both gaps from the task brief are closed:

- **Gap 1** (primary demo path never seen rendering): both clients now
  confirmed, through their own UI/network/render pipeline, to render all 6
  recommendations from both providers, interleaved by score, when a birth
  date is supplied.
- **Gap 2** (Android has no test for the provider-status branch order): the
  branching logic was extracted out of `ResultsActivity` into a plain-Java
  `ProviderStatusPresentation`, and a JVM unit test pins the branch order,
  with the branch-reversal experiment proving the test actually catches the
  regression.

## Commits

- `2de2e71` — feat(ios): extend demo hook + add DEBUG readout to verify full 6-row response
- `09064e3` — test(android): extract ProviderStatusPresentation and pin branch order with a unit test
- `3f49931` — feat(android): add DEBUG-only demo auto-submit hook for headless verification

## Edge check

```
$ grpcurl ${GRPC_HOST} list
funwithactivity.recommendations.v1.RecommendationsService
grpc.health.v1.Health
grpc.reflection.v1.ServerReflection
grpc.reflection.v1alpha.ServerReflection
```

Edge is up, no `-insecure`/`-plaintext` flag needed (publicly trusted cert).

Confirmed the full-response shape directly against the edge before touching
either client:

```
$ grpcurl -d '{"measurements":{"height_cm":175,"weight_kg":70,"birth_date_unix":631152000}}' \
    ${GRPC_HOST} funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations
{
  "recommendations": [
    {"title": "Drink more water", "source": "service1-stub", "score": 0.9},
    {"title": "Aim for 7–8 hours of sleep", "details": "Sleep is when the body recovers.", "source": "service2-stub", "score": 0.88},
    {"title": "Have more workouts per day", "details": "Workouts help.", "source": "service2-stub", "score": 0.75},
    {"title": "Improve your sleep schedule", "source": "service1-stub", "score": 0.65},
    {"title": "Walk more", "source": "service1-stub", "score": 0.4},
    {"title": "Add 20 push-ups to your morning", "details": "Small habits compound.", "source": "service2-stub", "score": 0.38}
  ],
  "statuses": [
    {"name": "service1-stub", "ok": true, "count": 3},
    {"name": "service2-stub", "ok": true, "count": 3}
  ]
}
```

Matches the table in the task brief exactly, including which rows carry
`details` (service2 rows only).

## Gap 1 — driving both clients with a birth date supplied

Neither client had a way to supply a birth date without a human tapping
through the UI (iOS's existing `-FWA_AUTOSUBMIT_DEMO` hook hardcoded the
switch off; Android had no hook at all). Both were extended minimally:

- **iOS**: `FWAMeasurementViewController` gained
  `-FWA_AUTOSUBMIT_DEMO_BIRTHDATE 1`, a second DEBUG-only launch argument
  read alongside the existing `-FWA_AUTOSUBMIT_DEMO 1`, which turns the
  birth-date switch on before submitting. `FWAResultsViewController` also
  gained a DEBUG-only `os_log` readout (subsystem
  `com.funwithactivity.ios`, category `results`) that enumerates exactly
  what it's about to render (score/source/title/hasDetails per row, one
  line per banner) — added because the existing network log only reported
  `hasResponse`/`error`, not response content, and a screenshot alone
  can't prove `hasDetails` for a field the UI doesn't currently surface.
- **Android**: `MeasurementActivity` gained a `BuildConfig.DEBUG`-gated
  auto-submit hook reading two boolean Intent extras
  (`com.funwithactivity.app.AUTOSUBMIT_DEMO`,
  `...AUTOSUBMIT_DEMO_BIRTHDATE`), the closest Android equivalent of the
  iOS launch-argument mechanism (Android has no launch-argument
  `NSUserDefaults` analogue; `am start` extras are the standard headless
  driving mechanism). Fills height=175/weight=70 and, if the birthdate
  extra is set, the birth date (1990-01-01T00:00:00Z, matching the value
  used in the edge check above), then taps submit after 500ms.

Both hooks are compiled out of / inert in release builds (`#if DEBUG` on
iOS, `BuildConfig.DEBUG` on Android) and go through the real
`GrpcClient`/`FWAGRPCClient` → real network round trip → real
`ResultsActivity`/`FWAResultsViewController` rendering code — nothing is
mocked or bypassed.

### iOS — build, test, and on-device verification

```
$ xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build
...
** BUILD SUCCEEDED **

$ xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' test
...
Test Suite 'FWAProviderStatusPresentationTests' passed at 2026-08-03 01:48:26.492.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.007 (0.008) seconds
** TEST SUCCEEDED **
```

Installed on simulator `iPhone 15 / iOS 17.5` (UDID
`15F6D5E7-46C4-4229-8624-8D707A839E9B`), streamed `os_log`, launched with:

```
$ xcrun simctl launch <udid> com.funwithactivity.ios \
    -FWA_GRPC_HOST ${GRPC_HOST} -FWA_GRPC_USE_TLS YES \
    -FWA_AUTOSUBMIT_DEMO 1 -FWA_AUTOSUBMIT_DEMO_BIRTHDATE 1
```

Captured log (exact output, subsystem `com.funwithactivity.ios`):

```
[network] GetRecommendations starting — host=${GRPC_HOST} heightCm=175.0 weightKg=70.0 hasBirthDate=1
[network] GetRecommendations closed — hasResponse=1 error=(null)
[results] Results screen — banners=0 recommendations=6
[results] recommendation[0] score=0.90 source=service1-stub title=Drink more water hasDetails=0
[results] recommendation[1] score=0.88 source=service2-stub title=Aim for 7–8 hours of sleep hasDetails=1
[results] recommendation[2] score=0.75 source=service2-stub title=Have more workouts per day hasDetails=1
[results] recommendation[3] score=0.65 source=service1-stub title=Improve your sleep schedule hasDetails=0
[results] recommendation[4] score=0.40 source=service1-stub title=Walk more hasDetails=0
[results] recommendation[5] score=0.38 source=service2-stub title=Add 20 push-ups to your morning hasDetails=1
```

Confirmed visually with a simulator screenshot (`Recommendations` screen,
no scrolling needed — all 6 rows fit): titles, sources and scores
(`0.90` / `0.88` / `0.75` / `0.65` / `0.40` / `0.38`) render exactly as
above, in that order, both `service1-stub` and `service2-stub` visible,
zero banners (both providers `ok`).

**iOS rendered rows (six, as displayed):**

| Score | Source | Title |
|---|---|---|
| 0.90 | service1-stub | Drink more water |
| 0.88 | service2-stub | Aim for 7–8 hours of sleep |
| 0.75 | service2-stub | Have more workouts per day |
| 0.65 | service1-stub | Improve your sleep schedule |
| 0.40 | service1-stub | Walk more |
| 0.38 | service2-stub | Add 20 push-ups to your morning |

No truncation, no zero/blank scores, no missing rows. Order matches the
brief exactly.

**Finding — `details` is never surfaced on iOS, for any row.**
`FWAResultsViewController`'s recommendation cell (`UITableViewCellStyleSubtitle`)
only has room for two text elements, and both are already spent on title
and "source · score"; `Recommendation.details` is read (the DEBUG log's
`hasDetails` flag proves it's present on the wire for the three
`service2-stub` rows) but nothing in the view hierarchy displays it. This
predates this task and isn't a regression from birth-date input — the
3-row (skip) case never had any `details`-bearing rows to expose it — but
it is exactly the kind of gap the brief asked to watch for, so it's
reported here rather than silently left. Not fixed in this task (it's a
UI redesign, out of scope for the two defined gaps); the caller should
decide whether it needs a pre-demo fix.

Regression check (birth date withheld, existing path): still renders
`banners=1` (`service2-stub skipped — required measurements not supplied`,
severity Info) and 3 `service1-stub` recommendations — unchanged by this
task's edits.

### Android — build, test, and on-device verification

```
$ ./gradlew clean assembleDebug
...
BUILD SUCCESSFUL in 2s
39 actionable tasks: 38 executed, 1 up-to-date

$ ./gradlew testDebugUnitTest
...
BUILD SUCCESSFUL in 1s
```

`app/build/test-results/testDebugUnitTest/TEST-...ProviderStatusPresentationTest.xml`:
```xml
<testsuite name="...ProviderStatusPresentationTest" tests="3" skipped="0" failures="0" errors="0" .../>
  <testcase name="skippedStatusWithErrorTextClassifiesAsInfoNotDegraded" .../>
  <testcase name="genuineFailureClassifiesAsDegraded" .../>
  <testcase name="okStatusClassifiesAsOk" .../>
```

Installed on `Medium_Phone_API_31_2` (already booted, `emulator-5554`),
driven via:

```
$ adb install -r app/build/outputs/apk/debug/app-debug.apk
$ adb shell am start -n com.funwithactivity.app/.features.measurement.MeasurementActivity \
    --ez com.funwithactivity.app.AUTOSUBMIT_DEMO true \
    --ez com.funwithactivity.app.AUTOSUBMIT_DEMO_BIRTHDATE true
```

Read back via `adb shell uiautomator dump` (exact text nodes, in on-screen
order):

```
service1-stub: 3 recommendation(s) in 0 ms
service2-stub: 3 recommendation(s) in 0 ms

Drink more water                       service1-stub   Score: 0.90
Aim for 7–8 hours of sleep             service2-stub   Score: 0.88
  "Sleep is when the body recovers."
Have more workouts per day             service2-stub   Score: 0.75
  "Workouts help."
Improve your sleep schedule            service1-stub   Score: 0.65
Walk more                              service1-stub   Score: 0.40
Add 20 push-ups to your morning        service2-stub   Score: 0.38
  "Small habits compound."
```

Confirmed with a screenshot as well (`android_results.png`) — cards render
in that order, `details` text visible under the title for `service2-stub`
rows only, absent for `service1-stub` rows, both provider banners green/OK
("N recommendation(s) in 0 ms" — not styled as skipped or error, since both
providers succeeded).

**Android rendered rows (six, as displayed):**

| Score | Source | Title | Details shown |
|---|---|---|---|
| 0.90 | service1-stub | Drink more water | (none) |
| 0.88 | service2-stub | Aim for 7–8 hours of sleep | "Sleep is when the body recovers." |
| 0.75 | service2-stub | Have more workouts per day | "Workouts help." |
| 0.65 | service1-stub | Improve your sleep schedule | (none) |
| 0.40 | service1-stub | Walk more | (none) |
| 0.38 | service2-stub | Add 20 push-ups to your morning | "Small habits compound." |

No truncation, no zero/blank scores, `details` correctly present for
`service2-stub` rows and correctly absent for `service1-stub` rows. Order
matches the brief exactly. Android does **not** have the iOS gap above —
`RecommendationAdapter` already binds `item.getDetails()` to a dedicated
`TextView` per card.

Regression check (birth date withheld): re-ran with only
`AUTOSUBMIT_DEMO=true`, confirmed unchanged output — 1 OK banner
(`service1-stub: 3 recommendation(s)...`), 1 skipped banner
(`service2-stub skipped — required measurements not supplied`), 3
`service1-stub` recommendations. The `ProviderStatusPresentation`
extraction did not change observable behavior.

## Gap 2 — Android provider-status branch order test

### What changed

- New: `android-client/app/src/main/java/.../features/recommendations/ProviderStatusPresentation.java`
  — pure Java (no `Context`/resources dependency), mirrors iOS's
  `FWAProviderStatusPresentation`. `forStatus(ProviderStatus)` classifies a
  status as `OK` / `INFO` / `DEGRADED`, branching on `skipped` **before**
  `ok`/`error`, exactly as the removed inline logic did and as
  `FWAProviderStatusPresentation` does.
- `ResultsActivity.renderStatusBanners` now calls
  `ProviderStatusPresentation.forStatus(status)` and switches on
  `getSeverity()` instead of inlining the `if (skipped) / else if (!ok) /
  else` chain directly — same rendered output, decision logic now
  extracted and unit-testable.
- New: `android-client/app/src/test/java/.../features/recommendations/ProviderStatusPresentationTest.java`
  — JVM unit test (`test/` source set, no instrumentation), three cases
  per the brief: `ok=true`, `ok=false/skipped=true` (with `error` also
  populated, matching the real wire format), `ok=false/skipped=false`.

### Branch-reversal experiment (proving the test isn't vacuous)

Temporarily reordered `forStatus()` to check `!status.getOk()` before
`status.getSkipped()`:

```java
public static ProviderStatusPresentation forStatus(ProviderStatus status) {
    if (!status.getOk()) {
        return new ProviderStatusPresentation(..., Severity.DEGRADED, ...);
    } else if (status.getSkipped()) {
        return new ProviderStatusPresentation(..., Severity.INFO, ...);
    } else {
        ...
    }
}
```

```
$ ./gradlew testDebugUnitTest --tests "...ProviderStatusPresentationTest"
...
com.funwithactivity.app.features.recommendations.ProviderStatusPresentationTest > skippedStatusWithErrorTextClassifiesAsInfoNotDegraded FAILED
    java.lang.AssertionError at ProviderStatusPresentationTest.java:60

3 tests completed, 1 failed

FAILURE: Build failed with an exception.
> There were failing tests. See the report at: .../app/build/reports/tests/testDebugUnitTest/index.html
```

XML detail:
```
<failure message="java.lang.AssertionError: expected:&lt;INFO&gt; but was:&lt;DEGRADED&gt;" .../>
```

**Exactly one test failed** — `skippedStatusWithErrorTextClassifiesAsInfoNotDegraded`
— and it failed for exactly the predicted reason (a populated `error` on a
skipped-but-reversed-priority status routes into `DEGRADED`). The other
two (`okStatusClassifiesAsOk`, `genuineFailureClassifiesAsDegraded`)
continued to pass, confirming they don't accidentally depend on branch
order and wouldn't mask a reintroduced defect. This matches the iOS
`FWAProviderStatusPresentationTests` branch-reversal result exactly
(see `docs/task-tls-repoint-report.md`).

Reverted the reversal, reran, all 3 pass again:

```
$ ./gradlew testDebugUnitTest
...
BUILD SUCCESSFUL in 761ms
```

`git diff` against the committed `ProviderStatusPresentation.java` is
clean after the revert (verified before committing).

## Verification summary

| Check | Result |
|---|---|
| `grpcurl ${GRPC_HOST} list` | 4 services listed, edge up |
| iOS `xcodebuild ... build` | `** BUILD SUCCEEDED **` |
| iOS `xcodebuild ... test` (FunWithActivityCoreTests) | `** TEST SUCCEEDED **`, 3/3 passed |
| Android `./gradlew clean assembleDebug` | `BUILD SUCCESSFUL` |
| Android `./gradlew testDebugUnitTest` | `BUILD SUCCESSFUL`, 3/3 passed (`ProviderStatusPresentationTest`) |
| iOS 6-row render (birth date supplied) | All 6 rows correct, in order, no truncation — see table above |
| Android 6-row render (birth date supplied) | All 6 rows correct, in order, no truncation — see table above |
| Branch-reversal experiment (Android) | Only the skip/error-conflict case fails when reversed; reverted and confirmed clean |

## Follow-up (2026-08-03) — iOS details parity fix + release-strip confirmation

Two items outstanding from the prior pass, both closed:

- **Fix**: iOS now renders `Recommendation.details`, matching Android.
- **Confirm**: release builds on both platforms strip the DEBUG-only demo
  auto-submit hooks. Confirmed for both; no fix was needed on either
  platform.

Commit: `9fd3a7a` — fix(ios): render recommendation details, matching Android

### Fix — iOS recommendation details

`FWAResultsViewController`'s recommendation cell was
`UITableViewCellStyleSubtitle`, which only has two text slots (`textLabel`
+ `detailTextLabel`), both already spent on title and "source · score" —
so `Recommendation.details` was read (proven present on the wire by the
DEBUG `hasDetails` log) but never displayed, even though Android already
rendered it (`RecommendationAdapter` binds `item.getDetails()` to a
dedicated `TextView`, `res/layout/item_recommendation.xml`).

Changes in `apple-client/FunWithActivity/Screens/FWAResultsViewController.m`:

- Added a private `FWARecommendationCell` (custom `UITableViewCell`
  subclass, same file) with three labels — title (body), details
  (footnote, `secondaryLabelColor`), and source/score meta (caption1,
  `secondaryLabelColor`) — stacked in a `UIStackView` pinned to the
  content view's `layoutMarginsGuide` on all four edges. This mirrors
  Android's visual hierarchy: details reads smaller and in a secondary
  colour, subordinate to the bold title, the same relationship as
  Android's `textAppearanceBody2` details under `textAppearanceSubtitle1`
  title.
- `recommendationCellForTableView:atIndex:` now sets
  `detailsLabel.hidden = !hasDetails` (in addition to leaving `.text` nil)
  when `recommendation.details` is empty — hiding an arranged subview
  removes it from the stack view's layout entirely, so service1-stub rows
  render with no label and no residual gap, not just empty text.
- `viewDidLoad` sets `tableView.rowHeight = UITableViewAutomaticDimension`
  and `estimatedRowHeight = 44` so rows self-size to whatever is actually
  visible (2 lines for service1-stub rows, 3 for service2-stub rows)
  instead of a fixed/hardcoded height that would either clip details or
  leave every row artificially tall.

Build + test (Debug, simulator):

```
$ xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build test
...
** BUILD SUCCEEDED **
...
Test Suite 'FWAProviderStatusPresentationTests' passed at 2026-08-03 02:05:19.320.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.006 (0.007) seconds
** TEST SUCCEEDED **
```

### Re-verification — full 6-row render on the live edge, with birth date supplied

Installed the rebuilt Debug app on the same booted simulator
(`iPhone 15 / iOS 17.5`, UDID `15F6D5E7-46C4-4229-8624-8D707A839E9B`),
streamed `os_log`, launched exactly as before:

```
$ xcrun simctl launch <udid> com.funwithactivity.ios \
    -FWA_GRPC_HOST ${GRPC_HOST} -FWA_GRPC_USE_TLS YES \
    -FWA_AUTOSUBMIT_DEMO 1 -FWA_AUTOSUBMIT_DEMO_BIRTHDATE 1
```

```
[network] GetRecommendations starting — host=${GRPC_HOST} heightCm=175.0 weightKg=70.0 hasBirthDate=1
[network] GetRecommendations closed — hasResponse=1 error=(null)
[results] Results screen — banners=0 recommendations=6
[results] recommendation[0] score=0.90 source=service1-stub title=Drink more water hasDetails=0
[results] recommendation[1] score=0.88 source=service2-stub title=Aim for 7–8 hours of sleep hasDetails=1
[results] recommendation[2] score=0.75 source=service2-stub title=Have more workouts per day hasDetails=1
[results] recommendation[3] score=0.65 source=service1-stub title=Improve your sleep schedule hasDetails=0
[results] recommendation[4] score=0.40 source=service1-stub title=Walk more hasDetails=0
[results] recommendation[5] score=0.38 source=service2-stub title=Add 20 push-ups to your morning hasDetails=1
```

Screenshot (`ios_results_with_details.png`, captured via
`xcrun simctl io <udid> screenshot`): all 6 cards visible with no
scrolling. Rendered exactly as follows, title in bold body text, details
(where present) directly under it in smaller secondary-grey text, then
"source · score" on its own line below:

| Score | Source | Title | Details rendered |
|---|---|---|---|
| 0.90 | service1-stub | Drink more water | *(no line, no gap)* |
| 0.88 | service2-stub | Aim for 7–8 hours of sleep | "Sleep is when the body recovers." |
| 0.75 | service2-stub | Have more workouts per day | "Workouts help." |
| 0.65 | service1-stub | Improve your sleep schedule | *(no line, no gap)* |
| 0.40 | service1-stub | Walk more | *(no line, no gap)* |
| 0.38 | service2-stub | Add 20 push-ups to your morning | "Small habits compound." |

All 6 rows present, scores descending 0.90 → 0.38 exactly as on the wire,
`service2-stub` rows show their details text, `service1-stub` rows show
no details and no empty gap (row height is visibly shorter for those
cards in the screenshot, confirming self-sizing works both ways), nothing
truncated, no zero/blank scores. iOS and Android now read as the same
product for this screen.

**Regression check** (birth date withheld, same as before): re-launched
with only `-FWA_AUTOSUBMIT_DEMO 1`. Output unchanged from the original
pass — `banners=1` (`service2-stub skipped — required measurements not
supplied`, severity Info), 3 `service1-stub` recommendations, all
`hasDetails=0`:

```
[network] GetRecommendations starting — host=${GRPC_HOST} heightCm=175.0 weightKg=70.0 hasBirthDate=0
[network] GetRecommendations closed — hasResponse=1 error=(null)
[results] Results screen — banners=1 recommendations=3
[results] banner[0] provider=service2-stub severity=1 message=service2-stub skipped — required measurements not supplied
[results] recommendation[0] score=0.90 source=service1-stub title=Drink more water hasDetails=0
[results] recommendation[1] score=0.65 source=service1-stub title=Improve your sleep schedule hasDetails=0
[results] recommendation[2] score=0.40 source=service1-stub title=Walk more hasDetails=0
```

### Confirm — release builds strip the DEBUG-only demo hooks

**Android** — built the release variant and checked both the R8 dead-code
report and the packaged dex directly:

```
$ ./gradlew assembleRelease
...
BUILD SUCCESSFUL in 28s
42 actionable tasks: 41 executed, 1 up-to-date
```

(No signing config is defined for `release` in `app/build.gradle` —
`assembleRelease` still succeeds because Gradle doesn't require signing
to *build* an APK, only to install/run it; `app-release-unsigned.apk` was
produced. No signing setup was faked.)

R8's own dead-code report
(`app/build/outputs/mapping/release/usage.txt`) lists the entire hook as
removed:

```
com.funwithactivity.app.features.measurement.MeasurementActivity:
    private static final long DEMO_BIRTH_DATE_UNIX
    public static final java.lang.String EXTRA_AUTOSUBMIT_DEMO
    public static final java.lang.String EXTRA_AUTOSUBMIT_DEMO_BIRTHDATE
    private void maybeAutoSubmitForDemoVerification(android.widget.Button)
```

Confirmed directly on the packaged dex (`strings` over every `classes*.dex`
extracted from each APK — release is a single `classes.dex` post-R8,
debug is multidex):

```
$ unzip -o -j app-release-unsigned.apk 'classes*.dex' -d release-dex
$ strings release-dex/*.dex | grep -i "AUTOSUBMIT\|maybeAutoSubmitForDemo"
(no output)

$ unzip -o -j app-debug.apk 'classes*.dex' -d debug-dex
$ strings debug-dex/*.dex | grep -i "AUTOSUBMIT\|maybeAutoSubmitForDemo"
'com.funwithactivity.app.AUTOSUBMIT_DEMO
"maybeAutoSubmitForDemoVerification
1com.funwithactivity.app.AUTOSUBMIT_DEMO_BIRTHDATE
EXTRA_AUTOSUBMIT_DEMO
EXTRA_AUTOSUBMIT_DEMO_BIRTHDATE
```

The debug APK's dex clearly carries all four strings (validating the
grep is capable of finding them); the release APK's dex has zero matches.
The `if (BuildConfig.DEBUG) { ... }` gating (`MeasurementActivity.java:81`)
is correctly stripped by R8 in the release build type
(`minifyEnabled true`). **No fix needed.**

**iOS** — built the Release configuration (simulator destination, to
avoid needing a device signing identity) and inspected the built binary
directly:

```
$ xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -configuration Release -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' \
    build
...
** BUILD SUCCEEDED **
```

Product: `FunWithActivity.app/FunWithActivity` (Mach-O universal, x86_64 +
arm64, 339,824 bytes — note this is a real linked binary, not the Debug
build's tiny stub-executor + `.debug.dylib` split used for incremental
builds):

```
$ strings FunWithActivity.app/FunWithActivity | grep -i \
    "FWA_AUTOSUBMIT_DEMO\|setUpAutoSubmitDemoHookIfRequested\|logRenderedContentForDemoVerification"
(no output)

$ nm FunWithActivity.app/FunWithActivity | grep -i \
    "AutoSubmitDemo\|logRenderedContentForDemoVerification"
(no output)

$ lipo -thin arm64 FunWithActivity.app/FunWithActivity -output FunWithActivity-release-arm64
$ strings FunWithActivity-release-arm64 | grep -ci "AUTOSUBMIT\|AutoSubmitDemo\|logRenderedContentForDemoVerification"
0
$ nm FunWithActivity-release-arm64 | grep -ci "AutoSubmitDemo\|logRenderedContentForDemoVerification"
0
```

Validated the methodology against the Debug build's
`FunWithActivity.debug.dylib` (where the actual Debug code lives, since
the top-level Debug executable is just a stub-executor loader) — all four
symbols/strings are present there:

```
$ strings FunWithActivity.app/FunWithActivity.debug.dylib | grep -i \
    "FWA_AUTOSUBMIT_DEMO\|setUpAutoSubmitDemoHookIfRequested\|logRenderedContentForDemoVerification"
FWA_AUTOSUBMIT_DEMO
FWA_AUTOSUBMIT_DEMO_BIRTHDATE
logRenderedContentForDemoVerification
setUpAutoSubmitDemoHookIfRequested

$ nm FunWithActivity.app/FunWithActivity.debug.dylib | grep -i \
    "AutoSubmitDemo\|logRenderedContentForDemoVerification"
000000000000118c t -[FWAMeasurementViewController setUpAutoSubmitDemoHookIfRequested]
0000000000004d4c t -[FWAResultsViewController logRenderedContentForDemoVerification]
... (block-invoke symbols, log-related globals) ...
```

This is stronger than Android's case: both hooks (`setUpAutoSubmitDemoHookIfRequested`
in `FWAMeasurementViewController.m` and the DEBUG-only `os_log` readout in
`FWAResultsViewController.m`) are behind `#if DEBUG` / `#endif`
preprocessor guards, and `GCC_PREPROCESSOR_DEFINITIONS` only defines
`DEBUG=1` in the project's Debug build configuration
(`FunWithActivity.xcodeproj/project.pbxproj`) — Release never defines it,
so the guarded code is never even compiled, not merely dead-code-eliminated
post-hoc. The binary evidence confirms this holds in practice. **No fix
needed.**

## Concerns

- ~~iOS defect: `FWAResultsViewController` never displays
  `Recommendation.details`~~ — **fixed** in `9fd3a7a` (see "Follow-up"
  above). Re-verified against the live edge: all 6 rows render correctly,
  details subordinate to title, no gap on rows without it.
- ~~Release-strip of the DEBUG-only demo hooks unconfirmed~~ — **confirmed**
  for both platforms (see "Follow-up" above): Android's hook is
  R8-dead-code-eliminated from `assembleRelease` output (verified via
  `usage.txt` and a direct dex string search); iOS's hooks are excluded at
  compile time by `#if DEBUG` (verified via `strings`/`nm` on the actual
  Release binary). Neither required a code fix.
- Android's `ResultsActivity` still owns banner *rendering* (color
  lookups, string formatting) — only the *classification* (`OK` / `INFO` /
  `DEGRADED`) was extracted. That was deliberate ("keep the extraction
  minimal") and matches the iOS split where
  `FWAProviderStatusPresentation` also owns message text but
  `FWAResultsViewController` owns cell styling/colors — Android's split is
  one level less integrated (Android's presentation object doesn't build
  the final display string, iOS's does) but the part that matters — branch
  order — is equally covered on both platforms now.
- Android's release build was never signed (no `signingConfig` on the
  `release` build type) — `assembleRelease` succeeds and R8 output was
  inspected directly, but the resulting APK cannot be installed/run
  as-is. Out of scope to fix per this task's instructions (do not fake a
  signing setup); flagging so it isn't mistaken for "release is fully
  ready to ship."
