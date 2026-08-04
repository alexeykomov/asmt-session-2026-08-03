# FunWithActivity — demo script (tabbed app, 1.2.0 onward)

**Audience:** C-level executives, in the room with PMs, an architect, and a tech lead. Five minutes. They do not read JSON — narrate outcomes, not payloads.

**This is the 1.2.0 script.** The product changed from a single measurement-form-and-submit screen to a tabbed app on all three clients — **Recommendations / Sources / Trends / Profile**, the Trends tab arriving in 1.3.0 — — web, iOS, Android — on the same day this script was written. `docs/demo-script.md` is the earlier 1.1.1 script; it still describes the form-and-submit app, and that build is genuinely still deployed as the fallback if 1.2.0 is unavailable on the day. Don't delete it, don't confuse the two on stage.

---

## Step 0 — Warming procedure (not optional)

Both vendor providers are AWS Lambdas behind API Gateway/Lambda URLs. They warm independently, and the first call after any idle period misses `app-server`'s 2-second per-provider timeout entirely.

**This matters more in 1.2.0 than it did before.** The app now opens directly on the Recommendations tab with height/weight already defaulted (175 cm / 70 kg), so it fetches on first paint — there is no form to stall on while you warm the backend out of the audience's sight. If you skip Step 0, the first thing the audience sees is the app opening cold: both providers unavailable, an empty table. There is no "before you submit" moment to hide behind anymore.

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

Or, better — warm through the actual deployed path, so you're also confirming the demo URL itself is up and exercising the same `/api/recommendations` endpoint the app calls:

```bash
# Repeat this 3 times, a few seconds apart, against the live demo URL
# ($WEB_APP_URL comes from .env — see .env.example)
curl -sS -X POST "$WEB_APP_URL/api/recommendations" \
  -H 'Content-Type: application/json' \
  -d '{"heightCm":184,"weightKg":84,"birthDateUnix":631152000,"faults":{}}' | head -c 400; echo
```

**Reading the response**: 1.2.0's wire format is a packed positional array, not a named-field object — `[recommendations[], statuses[]]`, where each status row is `[name, ok, skipped, error, count, latencyMs]` (index 1 is `ok` as `1`/`0`, index 5 is `latencyMs`). If you have `jq`, this is easier to read at a glance:

```bash
curl -sS -X POST "$WEB_APP_URL/api/recommendations" \
  -H 'Content-Type: application/json' \
  -d '{"heightCm":184,"weightKg":84,"birthDateUnix":631152000,"faults":{}}' \
  | jq '.[1] | map({name: .[0], ok: .[1], latencyMs: .[5]})'
```

**Confirm warm before proceeding**: the third call's status rows should show `ok` (index 1) as `1` for both `service1` and `service2`, with `latencyMs` (index 5) well under a second — expect roughly 60–150ms once warm, versus a 2000ms timeout miss when cold. If either still shows a failure on the third call, run it once more — do not start the audience-facing demo until both are warm.

### If a provider drops mid-demo, that is the demo

Warming gets both providers responding, but it does **not** make them stable — these
vendors are genuinely flaky, which is exactly what the customer's own brief warns about
("no guarantees on stability and availability"). `service2` fails roughly a third of calls
by design, and `service1` has been observed failing too — this is real vendor behaviour,
not a claim about one provider being more reliable than the other. Repeated identical
requests legitimately return different recommendations (the vendors draw fresh each call),
so don't be thrown if the row order or contents shift between an earlier rehearsal and the
live run.

Do not apologise for it or reach for the refresh control. Say this instead:

> "And there — one of your vendors just dropped out on its own. You can see the system
> kept the other one's results and told you which source is missing. That is the
> behaviour we designed for, and it's happening live rather than because I toggled it."

An unplanned failure that the system visibly survives is a stronger proof than the
toggle, because nobody can suspect it was staged. **If it happens mid-beat**, keep going
in whatever tab you're in — do not restart the demo. The Refresh control on the
Recommendations tab (see below) is there for exactly this: hit it, narrate the retry
openly, and continue. If a whole beat clearly won't land (e.g. the tab you need never
loads), say so once, move to the next beat, and come back if there's time. The toggle in
Step 0 of the arc below is still worth showing on purpose — it makes the point on demand —
but treat a real drop-out as a gift, not a problem.

**If you skip this step**, say so to no one — just don't skip it. If you get caught out anyway (cold demo, both providers dead on stage), the fallback is the section below: switch to stub providers live and keep going. Never apologize into dead air; narrate the switch as "let's not wait on the vendor — here's the same product running against synthetic data" and move on.

---

## Load-bearing behaviour before you go on stage: refresh-on-return

Every beat below is a **tab-to-tab gesture**: change something on Profile, switch to
Recommendations, and the screen is expected to move on its own. That "move on its own"
is refresh-on-return — Recommendations refetches automatically when you return to it
*if* something changed since the last fetch (a dirty flag), and does nothing if you
just tabbed away and back with no changes (so idle tab-switching doesn't burn a vendor
call). This is not a nice-to-have for the demo, it **is** the demo mechanism for two of
the three beats. If it's broken, the screen simply does not move when you switch back —
there is no error, no banner, nothing to point at. Rehearse both return trips (Profile →
Recs after a birth-date edit, Profile → Recs after a fault toggle) before you're on
stage, not for the first time in front of the customer.

There is also a manual **Refresh** control on the Recommendations tab. It forces a fetch
regardless of whether anything changed — use it if you want to retry a flaky vendor call
without first going and touching Profile.

---

## The arc (five minutes), as tab-to-tab gestures

### 1. Data minimisation — Recommendations → Profile → Recommendations (≈90s)

- Open on the **Recommendations** tab. It already has results: height and weight default
  to 175 cm / 70 kg, so the app opens on a real, populated, ranked table rather than an
  empty form. Point at the **blue, informational** banner — birth date is unset by
  default, so `service2` is already skipped, and the banner says so.
- **Say:** "Birth date is the one field we don't ask for by default. One of these two
  vendors legally cannot make a recommendation without it — the other doesn't need one at
  all — so today it's simply not being sent, and you can see that stated on screen, not
  hidden." Point at the Source column — every row says which vendor it came from.
- **Say the regulatory line plainly:** "This is GDPR Article 5(1)(c) data minimisation —
  collect only what's required for the purpose — and it's not a policy document, it's the
  actual behaviour you're looking at right now."
- Go to **Profile**. Set a birth date (the picker opens on a plausible default date so
  this is one gesture, not thirty years of scrolling).
- Return to **Recommendations**. It refetches on its own: more rows now render, the blue
  banner is gone, and — if a title happens to appear from both vendors — point at its
  Source column: it reads **`service1, service2`**, one row, not two. **Say:** "That's not
  luck, that's a dedupe pass on the merged set — two vendors independently suggesting the
  same thing collapses to one row, and it keeps whichever vendor's detail text the other
  one didn't supply. This is the merge-and-rank story made visible."
- Go back to Profile, clear the birth date (one click), return to Recommendations: fewer
  rows again, blue banner back. **Say:** "Supplying an age unlocks a provider rather than
  the app degrading when you withhold one — sharing more gets you more, and the product
  still works either way."

### 2. Resilience — Profile → DEVELOPER → Recommendations (≈90s)

- Stay on **Profile**, scroll to the **DEVELOPER** section — the fault toggles that used
  to live on the old form now live here, one per provider (a checkbox plus an error/
  timeout/malformed mode picker). Explain in one sentence that this is a presenter tool,
  not a customer-facing feature, if asked — don't dwell.
- Tick the fault toggle for one provider, leave the mode on its default ("error"), and
  return to **Recommendations**.
- **Say:** "I just killed one of the two vendors mid-session. This is exactly what
  happens in production when a third-party dependency goes down." Point at the
  **red, degraded banner** — visually distinct from the blue skip banner in beat 1 —
  appearing as soon as the screen refetches. The table still shows the surviving
  provider's recommendations; nothing goes blank.
- Untick the fault toggle on Profile and return to Recommendations before moving on, so
  the next beat (and the next presenter, if this runs back-to-back) starts clean.

### 3. Extensibility — Sources (≈60s)

- Open the **Sources** tab: both providers listed with live status and latency, pulled
  from the same response Recommendations already fetched (no extra vendor call just to
  show this screen).
- Tap into one provider's row: a **read-only** detail screen — configuration (name, type,
  base URL) and status (status pill, latency, last error verbatim, for whoever needs the
  raw text).
- Tap **`+`**: a stub add-source form. Fill it in and submit if you like — it never calls
  anything. **Say plainly:** "Adding a source at runtime isn't supported in this proof of
  concept, and we're not hiding that. Each provider has a different request shape, item
  schema and error envelope, so a new one means implementing the adapter interface,
  registering it, and adding a table test — that's a bounded engineering task, not an
  architecture change." That is the literal explanation text shown on screen — say it
  because it's true, not because it's the slide.

### 4. Optional — same backend, three clients (≈30s)

- If a rehearsed mobile device is available: open the same tabs on iOS or Android
  and show the same ranked list, the same banners, the same Sources screen, rendering
  natively.
- **Say:** "Same product, same backend, three clients — web, iOS, Android — all pointed
  at one session." This is the moment to gesture at the extensibility story without
  dwelling on it — skip if time is short; beats 1–3 are the required arc.

---

## Fallback plan — if the real vendors are down

If Step 0's warm-up still shows failures after a couple of retries, or a vendor genuinely goes down mid-session:

```bash
USE_STUB_PROVIDERS=true
```

Set this on the running deployment (or restart locally with it set) and the backend
switches to canned, synthetic recommendations. **The UI never lets fabricated data pass
as real**: stub providers name themselves `service1-stub` / `service2-stub`, and that
literal string is what renders in the Source column on every client — web, iOS, and
Android. Say this out loud if you use the fallback: "we're on synthetic data for this
vendor right now — you can see it labeled in the Source column — the product logic
you're watching is identical either way."

**Warning, and say this plainly if it comes up — do not attempt beat 2 on this path:**
fault injection is currently a **silent no-op against stubs**. The DEVELOPER toggles send
a fault keyed by provider name — `service1` / `service2` — but the stub registry names
its providers `service1-stub` / `service2-stub`, so the fault never matches anything and
quietly does nothing. Ticking the box, returning to Recommendations, and seeing no
degraded banner is *expected* on the stub fallback, not a bug you need to work around live
— just don't attempt the resilience beat on this path at all. Skip straight from beat 1 to
beat 3 if you're on stubs. Never let the audience discover the `-stub` suffix or the fault
no-op themselves; naming both yourself is what keeps this from reading as deception.

---

## One-line summary if asked to recap

"Two independent, unreliable third-party services, merged, deduplicated and ranked into one answer, browsable through four tabs — Recommendations, Sources, Trends, Profile — that gracefully drops to partial results under both a data-minimisation decline and a live vendor outage, on the same backend across web, iOS and Android."
