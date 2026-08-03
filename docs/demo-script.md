# FunWithActivity — demo script

**Audience:** C-level executives, in the room with PMs, an architect, and a tech lead. Five minutes. They do not read JSON — narrate outcomes, not payloads.

---

## Step 0 — Warming procedure (not optional)

Both vendor providers are AWS Lambdas behind API Gateway/Lambda URLs. They warm independently, and the first call after any idle period misses `app-server`'s 2-second per-provider timeout entirely. **Skip this step and the opening beat of the demo is both providers showing "unavailable" and an empty recommendations table** — this exact failure mode is real and reproducible, not a hypothetical.

Do this 5–10 minutes before the audience is watching, while you're still on small talk or setting up the room.

**Make at least three calls that hit both providers.** The cheapest way is to call the vendor Lambdas directly:

```bash
# Warm-up call 1 — $PROVIDER1_URL / $PROVIDER2_URL come from .env
# (see .env.example at the repo root)
curl -sS -X POST \
  "$PROVIDER1_URL" \
  -H 'Content-Type: application/json' \
  -d '{"height":184,"weight":84,"token":"service1-dev"}' | head -c 200; echo

curl -sS -X POST \
  "$PROVIDER2_URL" \
  -H 'Content-Type: application/json' \
  -d '{"measurements":{"mass":185.19,"height":6.04},"birth_date":631152000,"session_token":"'"$(uuidgen)"'"}' | head -c 200; echo

# Repeat the pair two more times (three total warm-up rounds)
```

### If a provider drops mid-demo, that is the demo

Warming gets both providers responding, but it does **not** make them stable — these
vendors are genuinely flaky, which is exactly what the customer's own brief warns about
("no guarantees on stability and availability"). Measured on the deployed app immediately
after a successful 3-call warm-up: the next request lost one provider again.

Do not apologise for it or reach for the refresh button. Say this instead:

> "And there — one of your vendors just dropped out on its own. You can see the system
> kept the other one's results and told the user which source is missing. That is the
> behaviour we designed for, and it's happening live rather than because I toggled it."

An unplanned failure that the system visibly survives is a stronger proof than the
toggle, because nobody can suspect it was staged. The toggle is still worth showing —
it makes the point on demand — but treat a real drop-out as a gift, not a problem.

Or, better — warm through the actual deployed path, so you're also confirming the demo URL itself is up:

```bash
# Repeat this 3 times, a few seconds apart, against the live demo URL
# ($WEB_APP_URL comes from .env — see .env.example)
curl -sS -X POST "$WEB_APP_URL/api/recommendations" \
  -H 'Content-Type: application/json' \
  -d '{"heightCm":184,"weightKg":84,"birthDateUnix":631152000}' | head -c 300; echo
```

**Confirm warm before proceeding**: the third call's `statuses` should show `"ok": true` for both `service1` and `service2` with `latencyMs` well under a second (expect roughly 60–150ms once warm, versus a 2000ms timeout miss when cold). If either still shows a failure on the third call, run it once more — do not start the audience-facing demo until both are warm.

**If you skip this step**, say so to no one — just don't skip it. If you get caught out anyway (cold demo, both providers dead on stage), the fallback is Step 5 below: switch to stub providers live and keep going. Never apologize into dead air; narrate the switch as "let's not wait on the vendor — here's the same product running against synthetic data" and move on.

---

## The arc (five minutes)

### 1. Enter measurements → merged, ranked recommendations, deduped, with provenance (≈90s)

- Open the measurement form. Enter height, weight, and a birth date.
- Submit.
- **Say:** "This just called two independent, real vendor services — not ours, not stubs — in parallel, merged their answers, removed duplicates, and ranked the result by a single score. Every row tells you which vendor it came from." Point at the Source column.
- If the raw vendor responses happened to contain a duplicate title, note it: "Both vendors actually suggested the same thing here — you're seeing one row, not two, because we dedupe before ranking."

### 2. Clear the birth date → a provider is skipped, results still render (≈60s)

- Clear the birth-date field only. Leave height/weight as-is. Submit again.
- **Say:** "One of these two vendors legally cannot make a recommendation without a birth date — the other doesn't need one at all. Watch what happens when I don't give it one."
- Point at the banner: it's **blue, informational**, not red — "this isn't an error, it's the system correctly declining to send data a provider doesn't need." The recommendations table still renders, just from the one provider that could work with what it has.
- **Say the regulatory line plainly:** "This is GDPR Article 5(1)(c) data minimisation — collect only what's required for the purpose — and it's not a policy document, it's the actual behavior you're looking at right now."
- Put the birth date back before the next step.

### 3. Tick the fault toggle → a provider dies, partial results still render (≈90s)

- Open the fault-injection panel (web only — this is a presenter tool, not a customer-facing feature; explain that in one sentence if asked, don't dwell).
- Tick the fault box for one provider, choose a mode (e.g. "error" or "timeout"), submit.
- **Say:** "I just killed one of the two vendors mid-session. This is exactly what happens in production when a third-party dependency goes down." Point at the degraded banner — **orange/red**, visually distinct from the blue skip banner in step 2 — appearing within about two seconds. The table still shows the surviving provider's recommendations; nothing goes blank.
- **Known quirk, only if it happens and only if you're running on the stub fallback (Step 5):** on the stub backend, the fault toggle silently does nothing on the very first submit of a session — it needs one prior successful response to learn the live provider names before it can target a fault correctly. If the toggle appears to no-op, submit once more without the fault (or just proceed — the warm-up calls in Step 0 already primed this against real providers, which is the default path and doesn't have this limitation).
- Untick the fault before moving on.

### 4. Optional — same result on iOS or Android over gRPC (≈60s)

- If a rehearsed mobile device is available: launch the app, submit the same measurements, and show the identical ranked list rendering natively.
- **Say:** "Same backend, same session, different transport — the phone talks gRPC directly to the same server the browser talks to over REST. One source of truth." This is the moment to gesture at the extensibility story without dwelling on it — skip if time is short; steps 1–3 are the required arc.

---

## Fallback plan — if the real vendors are down

If Step 0's warm-up still shows failures after a couple of retries, or a vendor genuinely goes down mid-session:

```bash
USE_STUB_PROVIDERS=true
```

Set this on the running deployment (or restart locally with it set) and the backend switches to canned, synthetic recommendations. **The UI never lets fabricated data pass as real**: stub providers name themselves `service1-stub` / `service2-stub`, and that literal string is what renders in the Source column on every client — web, iOS, and Android. Say this out loud if you use the fallback: "we're on synthetic data for this vendor right now — you can see it labeled in the Source column — the product logic you're watching is identical either way." Never let the audience discover the `-stub` suffix themselves; naming it yourself is what keeps this from reading as deception.

---

## One-line summary if asked to recap

"Two independent, unreliable third-party services, merged and ranked into one answer, that gracefully drops to partial results under both a data-minimisation decline and a live vendor outage — same product, three clients, one backend."
