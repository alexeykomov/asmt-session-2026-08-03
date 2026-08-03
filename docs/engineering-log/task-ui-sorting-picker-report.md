# Sortable results table (web) + birth-date picker collapse (iOS) — task report

## Status: both changes complete, committed separately, verified end-to-end

Commits:

- `7540ea2` — feat(web-client): sortable results table via goog.ui.TableSorter
- `9521c08` — fix(ios): collapse birth-date picker when disabled instead of ghosting it

---

## Change 1 — sortable results table (web-client)

### Files changed

- `ui-soy/components/recommendations-table.soy` — added `recs-th-sortable`
  affordance class to the Recommendation, Source and Score `<th>`s (Details
  left unstyled since it's unsortable). The table already had the
  `<thead>`/`<tbody>` structure `goog.ui.TableSorter` requires — no
  structural change needed.
- `web-client/src/features/recommendations/controller.js` — `goog.require('goog.ui.TableSorter')`;
  added `Controller.Column_` enum (0 Recommendation, 1 Details, 2 Source,
  3 Score); added `this.tableSorter_` field; added
  `attachTableSorter_(mount)`, called at the end of `renderTable_` on every
  render; disposes it in `disposeInternal`.
- `web-client/css/main.css` — pointer cursor + unsorted/ascending/descending
  glyph (⇅ / ↑ / ↓) on `.recs-th-sortable`, driven by TableSorter's own
  `goog-tablesorter-sorted` / `goog-tablesorter-sorted-reverse` classes
  (unrenamed — this project has no CSS renaming map).

### How it meets each requirement

- **Recommendation/Source alphabetical, Score numeric**: `setSortFunction`
  called explicitly per column (`alphaSort`, `alphaSort`, `numericSort`) in
  `attachTableSorter_` rather than relying on the library default.
- **Details explicitly unsortable**: `setSortFunction(Column.DETAILS, goog.ui.TableSorter.noSort)`.
- **Default stays server order until a click**: `TableSorter.decorate()`
  only wires up the click handler — it never sorts on its own — so no code
  change was needed to preserve this; confirmed by observation (first
  render always showed the descending-score order the server sent).
- **Re-attached after every submit**: `attachTableSorter_` disposes
  `this.tableSorter_` and creates a fresh instance against the freshly
  rendered `<table>` (queried via `goog.dom.getElementByClass('recs-table', mount)`)
  at the end of every `renderTable_` call, which itself runs on every
  submit. Verified with two submits in a row (see below) — sorting worked
  after both.
- **Compiles under ADVANCED, sorter not stripped**: `npm run build` (soy
  compile + Closure Compiler ADVANCED) succeeded, 0 errors. Grepped the
  compiled `public/main.min.js` for the two string literals TableSorter
  writes into class attributes at runtime (`goog-tablesorter-sorted`,
  `goog-tablesorter-sorted-reverse`) — both present, confirming the code
  path wasn't dead-code-eliminated. `main.min.js` came out at 22.2 KiB
  (up from whatever it was before TableSorter — no lint or type errors
  from `jscomp_error` checks in `web-client/scripts/compile.js`).

### Verification (commands + real output)

```
$ cd web-client && npm run build
...
0 error(s), 34 warning(s), 96.7% typed
main.min.js 22.2 KiB

$ npm run lint
> eslint src/**/*.js
(clean, no output)

$ grep -o "goog-tablesorter-sorted[a-z-]*" public/main.min.js | sort -u
goog-tablesorter-sorted
goog-tablesorter-sorted-reverse
```

Servers:
```
$ cd app-server && GRPC_PORT=51100 HEALTH_HTTP_PORT=51101 USE_STUB_PROVIDERS=true ALLOW_INSECURE_GRPC=true go run ./cmd/server &
{"level":"INFO","msg":"grpc server starting","port":"51100",...}
{"level":"INFO","msg":"http health sidecar starting","port":"51101"}

$ cd web-proxy && PORT=51102 APP_SERVER_URL=localhost:51100 node src/server.js &
{"level":"info","msg":"web-proxy listening","port":51102}
```

Driven in Chrome via the claude-in-chrome MCP tools against `http://localhost:51102/`:

1. Loaded the page — headers show ⇅ on Recommendation/Source/Score, no
   glyph on Details.
2. Submitted height=180, weight=80, birth date empty → 3 rows
   (service1-stub only; banner: "service2-stub skipped — required
   measurements not supplied"), default order descending by score
   (0.90, 0.65, 0.40) — matches server order, confirming no auto-sort on
   initial render.
3. Filled birth date (01/01/1990) and **submitted a second time** → 6 rows
   now (both providers), scores 0.90/0.88/0.75/0.65/0.40/(0.38 below fold).
   This is the re-render case that would break a once-only-bound sorter.
4. Clicked **Score** header → ascending: 0.38, 0.40, 0.65, 0.75, 0.88, ...,
   0.90 — up arrow shown. Clicked again → descending: 0.90, 0.88, 0.75,
   0.65, 0.40, ... — down arrow shown. **0.90 and 0.88 both present and
   correctly ordered both directions** — confirms numeric sort works on
   the exact pair called out in the brief. This was after the second
   submit, so it also confirms re-attachment.
5. Clicked **Recommendation** header → alphabetical ascending confirmed
   ("Add 20 push-ups...", "Aim for 7-8 hours...", "Drink more water",
   "Have more workouts...", "Improve your sleep schedule", ...); Score
   header's arrow reset to unsorted (single active sort column, as
   TableSorter tracks one `header_`).
6. Clicked **Details** header → no-op: row order and the Recommendation
   column's ascending arrow were both unchanged, confirming
   `noSort` blocks it correctly.
7. Clicked **Source** header → alphabetical ascending confirmed (all
   `service1-stub` rows grouped before all `service2-stub` rows).
8. Checked the browser console (`read_console_messages`, error-only
   filter) after all of the above — no errors.

### Concern / caveat worth flagging

The score column is always rendered as `scoreDisplay`, a `toFixed(2)`
string (pre-existing behavior, matching iOS/Android formatting) — so
every score in this app's data is a fixed 4-character `"0.XX"` string.
For strings of that shape, ASCII lexical comparison and numeric
comparison happen to agree (the differing digit is always in the same
position), so this specific dataset would not actually have visibly
demonstrated a lexical-vs-numeric bug even with a hand-rolled string
sort. `numericSort` is still the objectively correct, robust choice per
the brief (and the safety net against, e.g., a future score format
change, or a score ever reaching two integer digits) — worth knowing
this specific regression wouldn't have been visible on stage with a
lexical sort, only with different-width formatting.

---

## Change 2 — iOS birth-date picker collapse

### File changed

`apple-client/FunWithActivity/Screens/FWAMeasurementViewController.m`:

- In `buildUI`, the picker's `enabled`/`alpha` are now seeded from
  `birthDateSwitch.isOn` (was hardcoded `NO`/`0.4`), and a new
  `birthDatePicker.hidden = !birthDateSwitch.isOn` line collapses it in
  the `UIStackView` from the very first frame.
- `didToggleBirthDateSwitch` now toggles `hidden` (in addition to
  `enabled`/`alpha`) inside a `UIView animateWithDuration:0.25` block
  paired with `[self.view layoutIfNeeded]` — the supported pattern for
  animating a `UIStackView` arranged-subview collapse/expand.
- The hint label (`"One provider needs this..."`) was not touched — it
  stays an unconditional arranged subview above the picker, visible in
  both states.
- `didTapSubmit` was **not** touched — it already reads
  `birthDateSwitch.isOn` alone (never the picker's `enabled`/`hidden`) to
  decide whether to include `birthDateUnix`, so the GDPR skip semantics
  were never coupled to the visual bug and needed no change.

### Verification (commands + real output)

```
$ cd apple-client && xcodebuild -workspace FunWithActivity.xcworkspace -scheme FunWithActivity \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.5' build test
...
Test Suite 'FunWithActivityCoreTests.xctest' passed at 2026-08-03 12:29:12.034.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.006 (0.008) seconds
** TEST SUCCEEDED **
```

This environment has browser automation (claude-in-chrome) but no GUI
automation for the iOS Simulator, and `osascript`/System Events
accessibility automation was not authorized (`-1743 Not authorised to
send Apple events to System Events`), and `fb-idb` failed to run under
the installed Python 3.14 (`asyncio.get_event_loop()` — package is
unmaintained since ~2021). Rather than skip visual verification, I
temporarily added a **DEBUG-only, verification-only** method
(`TEMP_setUpToggleScreenshotHookIfRequested`, gated behind a
`TEMP_TOGGLE_DEMO` launch-argument default, mirroring the project's
existing `FWA_AUTOSUBMIT_DEMO` convention for headless verification)
that toggles the switch on at t+1.5s and off at t+3.5s with no human
tap required, took three `xcrun simctl io ... screenshot`s timed around
those triggers, then **reverted the temporary method before committing**
(`git diff` was inspected and confirmed to contain only the real fix
before `git add`).

Screenshots (all 3 in
`/private/tmp/claude-502/.../scratchpad/ios-screens/`, not part of the
repo):

1. **Toggle off (initial)** — no picker visible at all; "Get
   Recommendations" sits directly below the hint text. Confirms the
   ghost is gone.
2. **Toggle on** — picker fully expanded showing the wheel (Jan 1, 1990),
   pushing the button below off-screen. Confirms it expands.
3. **Toggle off again** — collapsed back to pixel-identical layout as
   state 1. Confirms it re-collapses, not just initial-hides.

Then rebuilt the clean (reverted) version and drove the real,
already-shipped `-FWA_AUTOSUBMIT_DEMO 1` hook (birth date off, the
GDPR-skip path) against a locally running app-server:

```
$ cd app-server && GRPC_PORT=51100 HEALTH_HTTP_PORT=51101 USE_STUB_PROVIDERS=true ALLOW_INSECURE_GRPC=true go run ./cmd/server &
$ xcrun simctl install <sim> .../FunWithActivity.app
$ xcrun simctl launch <sim> com.funwithactivity.ios -FWA_AUTOSUBMIT_DEMO 1 -FWA_GRPC_HOST localhost:51100 -FWA_GRPC_USE_TLS NO
```

Resulting Results screen: banner "service2-stub skipped — required
measurements not supplied", 3 recommendations, all `service1-stub`
(Drink more water 0.90, Improve your sleep schedule 0.65, Walk more
0.40). Confirms the GDPR data-minimisation skip path still works
end-to-end with the picker fix in place.

### Concerns

- The Simulator/GUI-automation gap above is an environment limitation,
  not a code concern — flagging it since the verification method (a
  temporary debug hook) is unusual and worth knowing about; it was fully
  reverted (`git diff` on the commit contains only the real fix — no
  `TEMP_` code was committed).
- Did not exercise VoiceOver/accessibility behavior of the newly-hidden
  picker (e.g. that `hidden = YES` correctly removes it from the
  accessibility tree, which it does by default for `UIView.isHidden`) —
  out of scope per the brief, but worth a follow-up pass if accessibility
  is part of this demo's story.
