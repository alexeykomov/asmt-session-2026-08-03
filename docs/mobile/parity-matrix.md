# Parity matrix — web / iOS / Android

Companion to [`ios-plan.md`](./ios-plan.md) and
[`android-plan.md`](./android-plan.md). One row per user-visible or
architecturally significant behaviour, one column per client. This is
meant to be read by the customer's architect alongside those two
documents — every ❌ below has a reason, and the reason is written out in
whichever plan document owns it, not hidden.

Legend: ✅ present and verified · ❌ absent (see note) · n/a not applicable
to this client's architecture.

| Behaviour | Web | iOS | Android | Note |
|---|---|---|---|---|
| Renders `ok` provider status (quiet, non-alarming) | ✅ | ✅ | ✅ | |
| Renders `skipped` status with its own informational styling | ✅ | ✅ | ✅ | Web: `.recs-banner-skipped`, blue/`--color-info`. iOS: `secondaryLabelColor` + `info.circle`. Android: `colorStatusSkipped{Bg,Text}` (`#E8F0FE`/`#1A3D8F`). All three read the skip reason from the server's `error` text, none hardcode the message. |
| Renders a genuine outage (`degraded`) with its own error styling, distinct from `skipped` | ✅ | ✅ | ✅ | Web: `.recs-banner-degraded`, red/`--color-danger`. iOS: `systemOrangeColor` + `exclamationmark.triangle`. Android: `colorStatusError{Bg,Text}` (`#FDECEA`/`#B3261E`). |
| Both `skipped` and `degraded` rendered simultaneously, visually unambiguous | ✅ | ✅ | ✅ | Verified on all three: two stacked banners, each in its own distinct box/style, against a real dual-failure response. |
| Score formatted to exactly 2 decimal places | ✅ | ✅ | ✅ | Web: `Controller.withFormattedScore_` → `toFixed(2)`. iOS: `%.2f`. Android: `score_format` = `"Score: %1$.2f"`. All three format client-side from the same raw-float wire value; none rely on the server to pre-round. |
| Recommendation `details` text displayed when present | ✅ | ✅ | ✅ | Web always renders a Details column (`—` when empty). iOS needed a fix in this project's history — the original two-slot subtitle cell had no room for it; now a dedicated `FWARecommendationCell`. Android had this correct from the start (`RecommendationAdapter` binds a dedicated `TextView`). |
| Full six-row response (both providers, birth date supplied) renders correctly, ordered by descending score, no truncation | ✅ | ✅ | ✅ | Verified against the live edge on all three; see `docs/task-mobile-verification-report.md` for the exact captured rows. |
| Fault-injection control (presenter demo tool) | ✅ | ✅ | ✅ | **Now on all three clients.** Reversed 2026-08-03 — it previously shipped web-only, and the original decision plus the reasoning behind it is preserved in [`fault-injection-decision.md`](./fault-injection-decision.md). It lives in a `DEVELOPER` section at the foot of Profile on each platform, the platform convention for debug controls. The original liability concern — a customer-installed binary should not carry a switch that degrades their own service — still stands for a shipped product, and is a build-configuration problem (exclude from release builds) rather than an architecture one. |
| Direct gRPC transport over TLS with a bearer token | n/a | ✅ | ✅ | Web talks REST to `web-proxy`, which is the one that speaks gRPC to `app-server`; there is no client-side gRPC channel to secure on the web path. Both mobile clients open their own TLS gRPC channel straight to the nginx edge and attach `authorization: Bearer <token>` on every call — see each plan's Transport section, including the Spike 1 (DigitalOcean App Platform / HTTP-1.1-only ingress) finding both plans document identically because it constrains both equally. |
| Device-sensor prefill: height/weight | n/a | ✅ | ❌ | iOS: HealthKit, real read, wired end to end. Android: **cut** — `connect-client`'s read APIs are Kotlin `suspend`/`KClass`-based with no verified pure-Java surface in this Java-only project; SDK-availability detection is real and wired, the actual read is not. See the Android plan's Health data section for the full reasoning and what a real fix would look like. |
| Device-sensor prefill: date of birth | n/a | ✅ | ❌ | iOS: HealthKit `dateOfBirthComponents`, works. Android: cut for the same reason as above, **and** independently impossible even if the language problem were solved — Health Connect has no birth-date record type at all; it only models measurements, not profile fields. Two separate reasons, both stated in the Android plan. |
| Offline / local response caching | n/a | ❌ | n/a | iOS: CoreData caching was spec'd, never built (no CoreData usage anywhere in `apple-client`) — every launch is a fresh network round trip. Android: no equivalent requirement was ever spec'd for this platform in this project, so there is nothing "missing" here to flag, only nothing built. Web: no offline concept applies to a server-rendered demo page. |
| `skipped`-before-`error` branch order pinned by an automated test proven to catch a regression | ✅ | ✅ | ✅ | iOS: `FWAProviderStatusPresentationTests` (3 cases); Android: `ProviderStatusPresentationTest` (3 cases) — both were deliberately branch-reversed once during development, the regression test failed exactly as predicted, and both were reverted before committing. Web: `web-client/test/provider-status-presentation_test.js` pins the same branch order with an automated test. |
| A release/production build produced by the toolchain | n/a | ✅ | ✅ | iOS: Release configuration builds successfully (simulator destination). Android: `assembleRelease` succeeds, R8 minification runs. |
| That release build signed and installable/distributable as-is | n/a | ❌ | ❌ | Neither platform has a real distribution-signing setup in this environment. iOS's Release build was only produced and verified for the Simulator, specifically to avoid needing a device signing identity that isn't available here — no TestFlight/device-signed build exists yet. Android's `release` build type has no `signingConfig` at all — `assembleRelease` produces `app-release-unsigned.apk`, which cannot be installed as-is. Both are flagged explicitly in their respective plans so neither gets mistaken for "ready to ship." |

## How to read the ❌ rows

Every absence above traces to one of three causes, and none of them is
"ran out of time and didn't notice":

1. **Deliberate product decision** (fault injection) — revisit only by
   making a new, explicit decision, not by treating this matrix as a todo
   list.
2. **Real platform/vendor constraint** (Health Connect's missing
   birth-date record type; DigitalOcean App Platform's HTTP/1.1-only
   ingress, which is why the edge tier exists at all) — not fixable from
   this codebase; the workaround or the alternative platform recommendation
   is already in place.
3. **Genuinely unfinished work, flagged rather than hidden** (CoreData
   caching, Health Connect's actual read path, both platforms' release
   signing) — real gaps, each with a stated reason and, where relevant, a
   description of what closing it would actually take.
