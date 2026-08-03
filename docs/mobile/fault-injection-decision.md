# Decision: fault-injection control stays web-only

> **REVERSED 2026-08-03 for the 1.2.0 clients.** Fault injection now ships
> on iOS and Android as well, inside a clearly-labelled `DEVELOPER` section
> at the foot of the Profile screen. The original decision and its reasoning
> are preserved below, unedited, because the reasoning did not turn out to
> be wrong — the context changed. See **Reversal** at the end.

## Decision

The fault-injection control (the "Fault injection (demo)" fieldset in
`ui-soy/pages/recommendations.soy`, wired up in
`web-client/src/features/recommendations/controller.js` via
`readFaults_`/`readFault_`/`bindFaultToggle_`, and sent to the backend as
the `faults` map on `GetRecommendationsRequest`) exists **only** on the
Closure/Soy web client. The iOS (Objective-C/UIKit) and Android (Java)
clients do **not** get an equivalent control, now or in any later parity
work, unless this decision is explicitly revisited.

## Rationale

- The fault toggle is a **presenter tool**: it lets whoever is driving the
  pre-sale demo kill `service1-stub`/`service2-stub` mid-session (e.g.
  `{"service1-stub":"timeout"}`) to show the audience the `ok=false,
  skipped=false` degraded-banner path on demand, without waiting for a
  real vendor outage.
- The web client is served fresh from a demo environment for every
  session and is never installed on anyone's device — there is no
  artifact to hand over, and no way for the control to leak into a
  customer's hands.
- Mobile clients are different: an iOS `.ipa`/TestFlight build or an
  Android `.apk`/Play build is a binary a customer (or a customer's IT
  department) can end up holding, inspecting, or side-loading. Shipping a
  "break this backend provider" switch inside that binary is a bigger
  liability than the convenience it buys a presenter — it is a
  fault-injection surface handed to whoever has the binary, in a way the
  web page never is.
- iOS and Android already correctly render all three provider outcomes
  (`ok`, `skipped`, degraded) they receive from whatever the backend
  actually returns — they just have no way to *request* a fault. That is
  the intended, accepted gap: the mobile clients are outcome-complete
  (they display everything correctly) without being trigger-complete
  (they cannot demand an outage). During a live demo, faults are injected
  from the web client (or directly against `app-server`'s `faults` map by
  the presenter) while all three clients are pointed at the same backend
  session, so the mobile UIs still visibly react to the induced outage —
  they just don't own the switch.

## Scope note for future parity work

> **Superseded — see Reversal below.** This paragraph is what the reversal
> reversed; it is kept so the record shows what was decided and when,
> rather than reading as though mobile fault injection had always been the
> plan.

This note exists so a later task writing the full iOS/Android parity plans
does not need to re-litigate this: **do not add a fault-injection UI to
either mobile client.** If product requirements change (e.g. a
presenter-only internal build with its own signing/distribution track
separate from anything a customer could receive), that would be a new
decision, made explicitly, not an extension of mobile parity work.

---

## Reversal — 2026-08-03

Fault injection now ships on all three clients. The 1.2.0 redesign moved
every client to a three-tab shell, and the fault toggles moved with the
measurements form into a `DEVELOPER` section at the foot of Profile.

**What changed was the context, not the argument.**

- **A named, conventional home appeared.** The original objection was to a
  loose "break this provider" switch sitting in a shipped binary. A
  `DEVELOPER` section at the bottom of a settings screen is the platform
  convention for exactly this on both iOS and Android — it is
  self-labelling, and it is where a reviewer expects debug controls to be.
- **Parity became the point.** Both demo beats now span two screens
  (Profile → Recommendations). With the toggles web-only, the resilience
  beat could not be performed on a phone at all, which undercuts the
  "same product, three clients, one backend" claim precisely when both are
  on screen together.
- **The audience for these binaries is the assessment**, not a customer.
  These builds are installed on a simulator and an emulator for a
  presentation; they are not distributed.

**The original concern still stands for a shipped product**, and should
gate any real release: a customer-installed binary must not carry a
control that can degrade their own service. The production answer is the
usual one — compile it out of release builds, or put it behind an
entitlement only internal accounts hold. That is a build-configuration
decision, not an architecture one, and it is deliberately not solved here.

**Revisit if** these binaries ever go to a real user, at which point the
control must be excluded from release builds before shipping.
