# Mobile parity plans + fault-toggle fix — task report

## Status

Both pieces complete.

- **Part 1** — fault toggle fixed: `web-client/src/features/recommendations/controller.js`
  now derives fault-map keys from the live provider names in the previous
  response's `statuses[]` (`Controller.providerNames_`, refreshed by
  `updateProviderNames_` on every successful response) instead of the
  hardcoded literals `service1`/`service2`. Seeded with the real-vendor
  names before any response exists (documented rationale in the code
  comment and in the commit message).
- **Part 2** — mobile parity docs written: `docs/mobile/ios-plan.md`,
  `docs/mobile/android-plan.md`, `docs/mobile/parity-matrix.md`.

## Commits

- `ec4f5fa` — `fix(web): derive fault-toggle keys from live provider names, not hardcoded strings`
- `11fc5d2` — `docs(mobile): write iOS/Android parity plans and cross-platform parity matrix`

## Fault-key fix verification

Verified live against both backends via the actual browser UI
(`claude-in-chrome`): against stubs (`USE_STUB_PROVIDERS=true`), the fault
checkbox no-ops on the very first submit of a session (documented,
expected — no prior `statuses[]` to learn names from) but correctly
degrades `service1-stub`/`service2-stub` on every submit after that;
against the real vendors (warmed up first, per the cold-Lambda note),
checking either fault box correctly degrades that exact real provider
(`service1` or `service2`) on the very first submit, confirmed by the
fault's telltale `latency_ms:0` server log line (an immediate synthetic
error, distinguishable from the real vendor's occasional genuine flakiness
observed during testing, which came back with real non-zero latencies).

## Concerns

- The fault toggle's fallback seed (`['service1', 'service2']`) means a
  fault checked on the *very first* submit of a fresh session against
  stub providers still silently no-ops, self-correcting from the second
  submit onward once a response has populated the real names. This is a
  documented, deliberate tradeoff (see the code comment in `controller.js`
  and the commit message) rather than an oversight — a presenter doing one
  fault-free warm-up submit before the demo (which they need to do anyway
  against the cold-start real Lambdas) never hits it in practice.
- The real vendor backend showed some independent flakiness during
  verification (a `service2` decode error, and an unrelated `service1`
  timeout on one call) unrelated to this fix — consistent with prior
  reports' notes on vendor error-taxonomy instability; not something this
  fix touches or could fix.
- The Android offline-caching parity-matrix row is marked `n/a` on the
  reasoning that no such requirement was ever spec'd for Android in this
  project (unlike iOS's CoreData, which was spec'd and cut) — this is an
  inference from absence of any Android-side offline-caching mention
  anywhere in the docs/reports read for this task, not a confirmed
  statement from a requirements doc; worth a sanity check with whoever
  owns the original Android scope if that distinction matters.
- Neither mobile client has a real distribution-signing setup verified in
  this environment (iOS Release was only built for Simulator; Android's
  `release` build type has no `signingConfig`) — flagged in both plan docs
  and the parity matrix so it isn't mistaken for "ready to ship."
