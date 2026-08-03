# Decision: fault-injection control stays web-only

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

This note exists so a later task writing the full iOS/Android parity plans
does not need to re-litigate this: **do not add a fault-injection UI to
either mobile client.** If product requirements change (e.g. a
presenter-only internal build with its own signing/distribution track
separate from anything a customer could receive), that would be a new
decision, made explicitly, not an extension of mobile parity work.
