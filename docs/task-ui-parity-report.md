# UI parity report — web / iOS / Android

Scope: three fixes to bring the web, iOS (Objective-C/UIKit), and Android
(Java) clients into visual/behavioural parity for how they render the
`ok` / `skipped` (GDPR data minimisation) / genuine-outage provider
outcomes and how they format recommendation scores; plus recording the
already-made decision to keep the fault-injection control web-only.

Commits (in order, on `main`):

- `2ffdfb9` — fix(web): give skipped provider status its own informational styling
- `2eb64cd` — fix(web): normalise recommendation scores to 2 decimal places
- `1647820` — docs: record fault-injection-stays-web-only decision for mobile parity

## Before/after parity table

| Aspect | Web (before) | Web (after) | iOS | Android |
|---|---|---|---|---|
| `skipped` status styling | Same red/pink box as a genuine outage (`#degradation-banner` had one danger-colored border/background, both `<p class="recs-banner-skipped">` and `<p class="recs-banner-degraded">` inherited it) | Own blue/neutral informational box (`.recs-banner-skipped`, `--color-info` #1a3d8f on `--color-info-bg` #e8f0fe) with an "ⓘ" icon, visually distinct from the red `.recs-banner-degraded` box | Already correct: `secondaryLabelColor` text on `secondarySystemBackgroundColor`, blue `info.circle` icon (`FWAResultsViewController.m:192-196`) | Already correct: `colorStatusSkippedText` (#1A3D8F) on `colorStatusSkippedBg` (#E8F0FE) (`ResultsActivity.java` + `colors.xml`) |
| Degraded/outage styling | Red danger box, same as skipped | Unchanged: red danger box (`.recs-banner-degraded`, `--color-danger`/`--color-danger-bg`), now with a "⚠" icon | Already correct: `systemOrangeColor` text/icon on `systemBackgroundColor`, `exclamationmark.triangle` icon | Already correct: `colorStatusErrorText` (#B3261E) on `colorStatusErrorBg` (#FDECEA) |
| Both skipped + degraded at once | Both rendered, but visually identical (both red) | Both rendered, each in its own distinct box (verified — see below) | Already correct (verified) | Already correct (verified) |
| Score precision | Raw float, variable precision (`0.95`, `0.398`, `0.6`, `0.04`, ...) | Exactly 2dp via `Controller.withFormattedScore_` (`toFixed(2)`), rendered from a new `scoreDisplay` field | Already correct: `%.2f` in `FWAResultsViewController.m:215` | Already correct: `R.string.score_format` = `"Score: %1$.2f"` |
| Fault-injection control | Web-only (fieldset in `ui-soy/pages/recommendations.soy`) | Unchanged — web-only, by design | None (by design) | None (by design) |

**What each mobile client did *before* my change, since the task asked me to check rather than assume:** both iOS and Android were *already* doing the right thing for both Fix 1 (skip vs. degraded styling) and Fix 2 (2dp score formatting). No mobile code was modified. Only the web client (`web-client/css/main.css`, `web-client/src/features/recommendations/controller.js`, `web-client/externs/api-response.js`) and the shared Soy source (`ui-soy/components/recommendations-table.soy`) changed. `ui-soy/components/degradation-banner.soy` was inspected and found already correct (it already emitted distinct `recs-banner-skipped`/`recs-banner-degraded` classes and read the skip reason from `$status.error`, not a hardcoded string) — the bug was entirely in `main.css` not styling those classes differently, so that file did not need a code change.

## Fix 1 — web skipped-vs-degraded styling

`web-client/css/main.css`: replaced the single red-bordered `#degradation-banner` container with a plain layout slot (`display:flex; flex-direction:column; gap:0.5rem` when non-empty) and gave each status its own box:

- `.recs-banner-skipped` — `--color-info` (#1a3d8f) on `--color-info-bg` (#e8f0fe), "ⓘ" icon — matches Android's `colorStatusSkipped{Text,Bg}` and iOS's blue `info.circle` treatment.
- `.recs-banner-degraded` / `.recs-banner-error` (the latter is the whole-request fetch-failure banner, a genuinely separate case, unchanged in intent) — kept the existing `--color-danger`/`--color-danger-bg`, "⚠" icon.

No change was needed to `ui-soy/components/degradation-banner.soy` — see above.

## Fix 2 — web score formatting

`web-client/src/features/recommendations/controller.js`: `renderTable_` now maps each recommendation through `withFormattedScore_`, which adds a `scoreDisplay` string field (`Number(score).toFixed(2)`) without changing the type of `score` itself (kept as the raw wire number, since `externs/api-response.js` declares `Object.prototype.score` as `number` for ADVANCED-mode property-renaming safety). `ui-soy/components/recommendations-table.soy` now renders `{$r.scoreDisplay}` instead of `{$r.score}`. `externs/api-response.js` gained a `scoreDisplay: string` extern for the same renaming-safety reason `score`, `title`, etc. are declared there.

## Fix 3 — fault toggle stays web-only

Recorded at `docs/mobile/fault-injection-decision.md`: the fault-injection fieldset is a presenter-only demo tool that must never ship inside an iOS/Android binary a customer could end up holding. No mobile code changed.

## Verification

### Backend used for all three clients

```
$ (cd app-server && GRPC_PORT=51100 HEALTH_HTTP_PORT=51101 USE_STUB_PROVIDERS=true \
    ALLOW_INSECURE_GRPC=true go run ./cmd/server &)
{"level":"WARN","msg":"INTERNAL_GRPC_TOKEN is unset; serving all RPCs without authentication because ALLOW_INSECURE_GRPC=true...."}
{"level":"WARN","msg":"USE_STUB_PROVIDERS=true: serving canned recommendations, not live vendor data","providers":["service1-stub","service2-stub"]}
{"level":"INFO","msg":"grpc server starting","port":"51100",...}
{"level":"INFO","msg":"http health sidecar starting","port":"51101"}

$ (cd web-proxy && PORT=51102 APP_SERVER_URL=localhost:51100 node src/server.js &)
{"level":"info","msg":"web-proxy listening","port":51102}
```

For the genuine-outage case I additionally ran the app-server **without**
`USE_STUB_PROVIDERS`, i.e. real `service1`/`service2` providers with
`PROVIDER1_URL`/`PROVIDER2_URL` unset — their `Fetch` fails immediately
(`Post "": unsupported protocol scheme ""`), which is a real transient
`ProviderError`, not a fabricated one. This let me trigger a genuine
degraded status on iOS/Android without any client-side fault-injection
hook (mobile intentionally has none — see Fix 3). Skip logic (birth date
omitted) is independent of stub-vs-real and works identically in both
modes, since it's driven by each provider's `Requires()` field set, not
by network reachability.

### Web

```
$ cd web-client && npm run build
...
0 error(s), 32 warning(s), 96.5% typed
main.min.js 15.0 KiB
```

(32 warnings are pre-existing `goog.inherits`/`goog.bind` deprecation
notices, unrelated to this change; confirmed unchanged by diffing against
a `git stash` baseline build.)

Served via web-proxy at `http://localhost:51102/` and driven with the
Chrome extension (`claude-in-chrome`):

- **Only-skipped** (height 180, weight 75, birth date blank, real
  unmocked round trip through the stub backend): banner rendered as
  `ⓘ service2-stub skipped — required measurements not supplied` in a
  light-blue box; table showed `service1-stub` recommendations with scores
  `0.90`, `0.65`, `0.40` (all 2dp).
- **Only-failed**: to reach this deterministically against the stub
  backend I had to work around a pre-existing, out-of-scope naming
  mismatch — the web UI's built-in fault checkboxes send fault keys
  `service1`/`service2` (matching the *real*-provider names in
  `app-server/internal/providers/registry.go`), but the stub providers
  are registered as `service1-stub`/`service2-stub`, so the checkbox's
  fault never reaches the stub it's checked against. (Confirmed via curl:
  `{"faults":{"service1-stub":"timeout"}}` degrades `service1-stub`
  correctly at the API level — `docs/task-ui-parity-report.md` verification
  log below.) To still exercise the real CSS/Soy rendering pipeline in the
  browser rather than only at the curl/API level, I monkey-patched
  `window.fetch` in the page (via `javascript_tool`) to return the exact
  JSON the real backend produces for a faulted `service1-stub`, then
  clicked the real "Get recommendations" submit button, driving the
  actual unmodified `Controller.renderBanner_`/`renderTable_` → Soy
  template → CSS. Rendered as `⚠ service1-stub unavailable — showing
  partial results` in a red box; table showed `service2-stub`
  recommendations with scores `0.88`, `0.75`, `0.38` (all 2dp).
- **Both at once** (skipped + failed together): same technique, statuses
  `[{service1-stub, ok:false, skipped:false}, {service2-stub, ok:false,
  skipped:true}]`. Both banners rendered stacked, each in its own box: red
  `⚠ service1-stub unavailable — showing partial results` above blue
  `ⓘ service2-stub skipped — required measurements not supplied`. Visually
  unambiguous — nobody would mistake one for the other.

This fault-key mismatch is a real, separate defect (the demo fault toggle
silently no-ops against a stub-mode backend) but is outside this task's
three assigned fixes; noting it here rather than silently working around
it. Filing it is recommended for a follow-up.

### iOS

```
$ cd apple-client && xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build
...
** BUILD SUCCEEDED **

$ xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' test
...
Test Suite 'FWAProviderStatusPresentationTests' passed at 2026-08-03 11:08:07.131.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.006 (0.007) seconds
** TEST SUCCEEDED **
```

Installed on the already-booted `iPhone 15 (15F6D5E7-46C4-4229-8624-8D707A839E9B)`
simulator and driven via the existing DEBUG-only `-FWA_AUTOSUBMIT_DEMO`
launch-argument hook (see `docs/task-mobile-verification-report.md`) —
real gRPC round trip, real `FWAResultsViewController` rendering, nothing
mocked:

```
$ xcrun simctl launch <udid> com.funwithactivity.ios \
    -FWA_GRPC_HOST localhost:51100 -FWA_GRPC_USE_TLS NO -FWA_GRPC_TOKEN testtoken123 \
    -FWA_AUTOSUBMIT_DEMO 1
```

Against the real-provider (unconfigured URL) backend — genuine
skip+degraded combo in one shot:

```
[network] GetRecommendations starting — host=localhost:51100 heightCm=175.0 weightKg=70.0 hasBirthDate=0
[network] GetRecommendations closed — hasResponse=1 error=(null)
[results] Results screen — banners=2 recommendations=0
[results] banner[0] provider=service1 severity=2 message=service1 unavailable — showing partial results
[results] banner[1] provider=service2 severity=1 message=service2 skipped — required measurements not supplied
```

On screen: `service1 unavailable — showing partial results` in **orange**
with a warning-triangle icon on a plain white row; `service2 skipped —
required measurements not supplied` in **secondary gray** with a blue
info-circle icon on the app's secondary background — clearly two
different treatments, stacked, both visible at once.

Then against the stub backend with `-FWA_AUTOSUBMIT_DEMO_BIRTHDATE 1`
(pure `ok` case, no banners) to check score formatting:

```
[results] Results screen — banners=0 recommendations=6
[results] recommendation[0] score=0.90 source=service1-stub title=Drink more water hasDetails=0
[results] recommendation[1] score=0.88 source=service2-stub title=Aim for 7–8 hours of sleep hasDetails=1
[results] recommendation[2] score=0.75 source=service2-stub title=Have more workouts per day hasDetails=1
[results] recommendation[3] score=0.65 source=service1-stub title=Improve your sleep schedule hasDetails=0
[results] recommendation[4] score=0.40 source=service1-stub title=Walk more hasDetails=0
[results] recommendation[5] score=0.38 source=service2-stub title=Add 20 push-ups to your morning hasDetails=1
```

All 2dp, confirmed both in the log and on screen (screenshot showed
"score 0.90" / "score 0.88" / ... "score 0.38").

### Android

```
$ cd android-client && ./gradlew assembleDebug testDebugUnitTest
...
BUILD SUCCESSFUL in 1s
45 actionable tasks: 14 executed, 31 up-to-date
```

(`testDebugUnitTest` includes `ProviderStatusPresentationTest`, which
passed as part of the aggregate task; no failures reported.)

Installed and driven on the already-booted `Medium_Phone_API_31_2`
(Android 12) emulator, pointed at the local backend:

```
$ ./gradlew installDebug -PserverHost=10.0.2.2:51100 -PserverTls=false -PserverToken=testtoken123
...
BUILD SUCCESSFUL in 2s
```

- **Only-skipped** (height 180, weight 75, date of birth left "Not
  supplied", stub backend, real tap-through the actual UI): rendered
  `service1-stub: 3 recommendation(s) in 0 ms` in green (the quiet "ok"
  treatment) plus `service2-stub skipped — required measurements not
  supplied` in a light-blue box with dark-blue text; recommendation cards
  showed scores `0.90`, `0.65`, `0.40` — all 2dp.
- **Both at once** (same form state, but against the real-provider
  unconfigured-URL backend, so `service1` genuinely fails while
  `service2` is genuinely skipped): rendered `service1 unavailable —
  showing partial results (service1: [0] Post "": unsupported protocol
  scheme "" (transient))` in a **red/pink** box directly above
  `service2 skipped — required measurements not supplied` in a
  **light-blue** box. Two distinct, stacked, unmistakable treatments —
  this is Android's own `colorStatusError{Bg,Text}` vs.
  `colorStatusSkipped{Bg,Text}`, exactly as intended, exercised through a
  genuine backend failure with no test-only code paths.

## Concerns / follow-ups

- The web fault-injection UI's checkbox fault keys (`service1`/`service2`)
  don't match the stub backend's provider names (`service1-stub`/
  `service2-stub`), so the presenter's fault toggle silently does nothing
  when demoing against `USE_STUB_PROVIDERS=true`. It works correctly
  against real providers (matching names). Worth a follow-up ticket; not
  fixed here since it's outside this task's three assigned fixes.
- `web-client`'s `npm run lint` already fails at baseline (155
  pre-existing errors, entirely in generated/gitignored template files
  plus pre-existing indentation-rule violations in hand-written files) —
  confirmed via `git stash` before touching anything. My changes add 5
  more violations of the same pre-existing `indent` rule in
  `controller.js`, consistent with the file's existing (already
  non-conformant) style; `npm run build` (the actual gate named in this
  task) is unaffected and passes with 0 errors.
