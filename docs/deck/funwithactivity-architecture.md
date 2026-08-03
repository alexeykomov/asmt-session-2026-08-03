# FunWithActivity — Architecture

**Pre-sale technical session · PMs, architect, tech lead**

---

## 1. What you're building, and why this session is graded the way it is

- A health/activity recommender: connect any consumer health hardware, normalise what it collects, return behavioural recommendations (sleep, hydration, activity).
- Loyalty tiers, a social layer, reseller and gym integrations on the roadmap.
- You asked us to (a) design this to be genuinely extensible, and (b) recommend a cloud provider with reasoning. Both are graded questions, not throwaway lines.
- We're going to show you working code, not just slides — a live gRPC backend, a web client, an iOS client, and an Android client, all talking to your real vendor services.

**Speaker notes:** Open by naming the format: ~20 slides, then a five-minute live demo, then we take live-coding requests. Set expectations that this is a working session — several slides end in a question we're asking *you*, not just a statement we're making. That framing matters for slide 20.

---

## 2. Five forces from your brief, and the lawsuit named directly

1. Extensibility — "more services/devices are to be added soon."
2. Scale — aggressive growth, resellers, gyms, global rollout after a regional pilot.
3. Data sensitivity — health data, GDPR, a loyalty/social layer sitting on top of it.
4. Reliability — hardware and vendor integrations you don't control.
5. A cloud recommendation, reasoned, not asserted.
- **You settled a lawsuit alleging user data loss.** We are not treating that as background. Every architectural choice in this deck — the erasure mechanism, the durability controls, the plane separation, the per-region cells — is legible against that fact, and we'll say so explicitly as we go rather than making you connect the dots.

**Speaker notes:** This slide is deliberately blunt. Health companies get pitched generic "secure, scalable, compliant" decks constantly; naming the lawsuit up front signals we read the brief as engineers, not as a sales team. Pause here — let it land — before moving to architecture.

---

## 3. High-level architecture, and the five extension seams

**Diagrams for this slide and the next four architecture-heavy slides are in
`docs/architecture-diagrams.md`** — system topology (and why mobile bypasses
`web-proxy` entirely), the request flow for one recommendation call (the
ok/skipped/degraded distinction), and the five extension seams below, drawn out.

```
Clients: Web (Closure) · iOS (Obj-C/UIKit) · Android (Java)
              │ REST                    │ gRPC + bearer token
       ┌──────▼──────┐                  │
       │  web-proxy  │ (Node, REST façade)
       └──────┬──────┘                  │
              │ gRPC                    │
       ┌──────▼──────────────────────────▼──────┐
       │        nginx edge (TLS, routing)        │
       └──────────────────┬───────────────────────┘
                           │ gRPC / h2c
                  ┌────────▼────────┐
                  │  app-server (Go) │  fan-out · normalise · rank · dedupe
                  └───┬─────────┬────┘
                      │         │
              ┌───────▼──┐ ┌────▼──────────────┐
              │ Postgres │ │ Recommendation      │
              │ (state)  │ │ providers (external) │
              └──────────┘ └──────────────────────┘
                  + ClickHouse (health events) / ClickHouse (analytics), designed
```

- **"Extensible" is not one seam, it's five**: (1) recommendation provider, (2) device/sensor, (3) partner/reseller, (4) client app, (5) internal service.
- **The organising rule: gRPC is the boundary for things we control on both ends. Adapters and REST are the boundary for things we don't.** Browsers can't speak gRPC without a proxy; resellers won't integrate over gRPC; your vendors speak whatever HTTP/JSON they speak, not our choice.

**Speaker notes:** Your brief names seams 1 (providers) and 2 (devices) explicitly. Seam 3 (resellers/gyms) is directly implied by your "expanding aggressively" language — we're calling it out because most decks miss it. This rule is the one-sentence answer if the architect asks "how do you decide gRPC vs REST vs adapter" at any later slide — point back here.

---

## 4. The device framework, and the FHIR-aligned canonical model

"Work with any physical hardware on the market" is not "build one integration per device" — that's an infinite backlog. Four adapter classes cover the market:

| Class | Mechanism | Covers |
|---|---|---|
| Platform health stores | HealthKit, Health Connect | Apple Watch + everything that writes to the store — the large majority |
| Vendor cloud APIs | OAuth2 + webhooks | Fitbit, Garmin, Oura, Withings, Polar |
| BLE GATT standard profiles | Heart Rate, Weight Scale, Cycling Speed | Unbranded/generic hardware direct to phone |
| Manual entry | UI | Everything else — and today's PoC path |

- Every adapter normalises into an internal model **aligned to HL7 FHIR `Observation`** — code, subject, effective time, UCUM-unit value, device reference. Not a FHIR *server* for the pilot — FHIR-*aligned* structures.
- Why: health interoperability is a solved problem; all three hyperscalers offer a managed FHIR store, so this doesn't lock us to one vendor; your own reseller/gym/insurer roadmap already speaks FHIR.
- Adding a device is **registering an adapter, not changing the core.** That's the concrete answer to your requirement #1.

**Speaker notes:** This is the worked example for "extensibility" — don't just assert the interface exists, walk through what adding, say, a Garmin OAuth adapter would actually touch: implement `DeviceAdapter`, register a capability set, done. If asked why not build a full FHIR server now: FHIR alignment is deliberately the cheaper, reversible bet — adopting a managed FHIR service is a phase-2 decision the model is already compatible with. This also seeds slide 12's Azure condition.

---

## 5. Recommendations pipeline — canonical model, ranking, and our own sharpest objection

```go
type Measurements struct {
    HeightCm  float64
    WeightKg  float64
    BirthDate *time.Time // optional
}
```

- Conversion lives in each adapter, never the core: Service 1 wants metric + a constant token; Service 2 wants imperial + a fresh UUID per call.
- **The DOB asymmetry is a feature.** Service 1 doesn't need birth date; Service 2 does. `Requires()` turns that into a declarative routing rule — the aggregator skips a provider whose required fields are missing. Demonstrable in ten seconds (slide 15, and live in the demo).
- Ranking: `Final = NormScore × Weight[Source]`, stable-sorted descending, weights from an env var (no rebuild — this is a rehearsed live-coding ask).
- **We're naming our own weakness before you do:** Service 1's `confidence` is model certainty; Service 2's `priority` is editorial importance. Normalising both onto one 0..1 axis is a judgment call, and the weights are where that judgment lives. The production answer is calibrating weights against outcome data — did the user act on the recommendation — not a hardcoded constant.

**Speaker notes:** Volunteering the confidence-vs-priority weakness converts the architect's sharpest likely objection into agreement before they raise it. If pressed on calibration: that requires the recommendation-outcomes data in Postgres (slide 13) feeding back into the `Ranker`, which is designed but not built.

---

## 6. Finding — your own brief is wrong about your services

This is the first of four findings we're handing back to you, not complaining about. We built against your written brief first; then we hit your live endpoints and found the real contract differs from the documented one, on **both** services. Corrected contracts are already written up in `docs/integrations/service1.md` and `service2.md`.

| | What the brief shows | What's actually deployed |
|---|---|---|
| Envelope | The inner payload only | Every response wrapped in an **AWS Lambda proxy envelope** — `body` is a JSON *string*, parsed twice |
| Service 2 success shape | `{"recommendations": [...]}` | A **bare array**, identical in shape to Service 1's — the documented key doesn't exist |
| Provider errors | Implied to use HTTP status | Arrive over **HTTP 200**, with a `statusCode` field inside the body that doesn't match the real transport status |
| Schema violations | Not documented | A **third**, unrelated shape — FastAPI's own HTTP 422 `{"detail": [...]}` |

**Speaker notes:** Land this as evidence, not accusation: "we verified this against your live endpoint and your own OpenAPI document; here's the diff." The old adapter, built strictly to the brief, would have silently returned zero Service 2 recommendations on every real call — that's a concrete, quantifiable near-miss to cite if asked why this matters.

---

## 7. Finding — your error codes are not a reliable signal

- Your documented quirk: `errorCode 39` with a misleading "Short of Memory!" message actually meant an invalid token. We implemented that check exactly as specified.
- Then we ran **25 invalid-token calls** against your live endpoint. `errorCode 39` did not recur once. We got a different code almost every time — 5, 6, 9, 10, 19, 21, 22, 26, 29, 31, 32, 33, 40, 41, 46, 57, 63, 67, 69, 70, 71, 73, 77, 79, 83, 87, 91, 99 — each with a different canned message, always at `statusCode 503`.
- **There is no stable signal to classify failures on from your error payload alone.** That is why the adapter classifies on transport-level facts — `statusCode >= 500` → transient/retryable — rather than parsing vendor codes or message text, which we've now shown are not trustworthy.
- Consequence we're flagging honestly: most real invalid-token failures fall through to "transient" and get retried, which is the wrong call for a credential that will never become valid. We kept the documented check because you asked for it explicitly, but it will rarely fire in practice.

**Speaker notes:** This is a gap in your own error contract, not something we can adapt around reliably from our side. The ask for you: either a stable error code per failure class, or an explicit field we can classify on. Frame this as a question we need answered before production, not just a PoC footnote.

---

## 8. Finding — your responses contain duplicates, so dedupe is a real requirement

- Observed live: the **same title repeated within a single provider's response** — `"Don't eat carbs!"` three times in one Service 1 call.
- Observed live: the **same title from both providers in the same session** — `"Go for a physical check up"` appearing from Service 1 and Service 2 together.
- The design spec originally shipped dedupe as a no-op behind an interface, on the assumption duplicates were theoretical. They are not — this is measured, not hypothetical.
- Fixed: `ExactTitleDeduper`, applied to the merged cross-provider set after fan-out and before ranking, keeps the highest-scoring instance of each exact title. You'll see this live — a request that returns duplicates from the raw provider calls renders a clean, deduplicated table.

**Speaker notes:** The honest caveat: this matches on exact title text only. If a vendor ever returns the same title with different detail text, one instance's details get silently dropped along with its score — flagged, not fixed, since there's no evidence yet that it happens. The proven, harder answer for near-duplicates ("walk more" vs "have more workouts per day") is a recommendation-intent taxonomy adapters map onto — designed, not built.

---

## 9. Resilience engineering, and the finding that shapes today's demo

- Fan-out via `sync.WaitGroup` with a per-provider result struct — **not** `errgroup`, which short-circuits on the first error and destroys single-provider-failure isolation.
- Per-provider `context.WithTimeout` at 2s; a tuned singleton `http.Client` at package init; `io.LimitReader` at 8 MiB before JSON decode; a `Cache` interface with a `NoopCache` default (Redis in production).
- Fault injection: a wrapper implementing the same `Provider` interface, toggled per-request from the UI — no restart needed, two people can hit it concurrently.
- **Finding: cold-start latency is real and measured.** Each vendor's Lambda warms independently. The first call after idle time misses the 2s timeout entirely and both providers report failed; a warm call answers in 60–120ms. It takes roughly **three calls before both providers are reliably warm.**
- **This is why the demo has a warming procedure**, and why we're telling you now rather than letting you discover it live: skip the warm-up and the opening beat of the demo is an empty results table with both providers unavailable.

**Speaker notes:** This is a real vendor-infrastructure characteristic, not a bug in our fan-out logic — cite the timing numbers if asked (2000ms `PROVIDER_TIMEOUT_MS` default vs. observed cold-start latency exceeding it on first call, then sub-150ms on warm calls). Bridges directly into the cloud-hosting finding on the next slide and into the demo script's Step 0.

---

## 10. Finding — gRPC does not survive DigitalOcean App Platform's ingress

- Spike 1, run early deliberately, before betting the schedule on it: DigitalOcean App Platform's ingress (Envoy) proxies **HTTP/1.1** to containers. Our Go gRPC server speaks h2c only.
- Verified empirically: `grpcurl` against the deployed port returns `upstream connect error … reset reason: protocol error`; a plain `curl` to the same port negotiates HTTP/1.1 and times out.
- **This is a limitation of one PaaS, not of the architecture.** AWS ALB with a gRPC target group, GCP Cloud Run, and Azure Container Apps all speak HTTP/2 to targets natively — the production recommendation is unaffected.
- **This is why an nginx edge tier exists**: TLS termination with a real Let's Encrypt certificate (iOS ATS and Android's default network security config both reject self-signed certs) plus `grpc_pass` in front of App Platform, giving native clients a route gRPC can actually traverse. Browsers go through `web-proxy` (REST, HTTP/1.1) and never hit this limitation at all.
- This finding independently supports a position we're stating outright on slide 18: **PoC hosting is not the production target.** The PoC processes no PHI — every input here is a value typed into a form — so hosting was chosen for iteration speed. Production is AWS, with a BAA and EU residency.

**Speaker notes:** If the tech lead asks "why not just fix DigitalOcean" — you can't; it's ingress behavior, not configuration. If asked why not switch PoC hosting to AWS now — because the PoC intentionally carries no real user data, so the cost of that limitation is an edge-tier workaround, not a redesign, and switching hosting mid-PoC costs more than it buys.

---

## 11. Cloud recommendation — criteria and head-to-head

**The finding that comes first: the architecture is deliberately cloud-neutral, so this decision is reversible.** Go services in containers, PostgreSQL, self-hosted ClickHouse, object storage — every component has a direct equivalent on all three providers. No managed proprietary database, no serverless lock-in. That reframes this from an irreversible bet into a first-phase choice.

| # | Criterion | Why it matters here |
|---|---|---|
| 1 | HIPAA eligibility + BAA | Post-lawsuit posture |
| 2 | EU residency / sovereignty | GDPR Art. 9, EU-first pilot, post-Schrems II |
| 3 | Managed FHIR / health services | Only if phase 2 adopts FHIR as system of record |
| 4 | Key management for provable erasure | The crypto-shred design (slide 14) depends on it |
| 5 | Operational fit for self-hosted ClickHouse | Local-NVMe families, object-tiering maturity |
| 6 | Region breadth | Per-region cell rollout |
| 7 | Cost shape, pilot → global | |
| 8 | Exit cost | See above |
| 9 | Team and partner depth | Defensibility under live questioning |

| | AWS | Azure | GCP |
|---|---|---|---|
| HIPAA/BAA | Broadest catalogue | Strong, simplest w/ enterprise agreement | Solid |
| EU residency | `eu-central-1`/`eu-west-1` + announced European Sovereign Cloud | **Clearest formal commitment** — EU Data Boundary | Sovereign Controls; fewer regions |
| Managed FHIR | HealthLake | **Health Data Services + MedTech connector** | Cloud Healthcare API |
| ClickHouse hosting | **Strongest** — `i`-family NVMe canonical host, S3 the most battle-tested cold tier | AKS + `Lsv3` NVMe, less proven | GKE good, local SSD good |
| Distinctive analytics | — | — | BigQuery — **but we're not using it** |

**Speaker notes:** Say the cloud-neutrality point *before* naming a provider — it changes how the recommendation lands. This slide is data; verdict is next slide.

---

## 12. Cloud recommendation — AWS, and the condition that would flip it to Azure

**Recommendation: AWS**, on three criteria — none of them "AWS is biggest":

1. **ClickHouse operational fit.** The largest, most demanding, self-hosted component in the platform. AWS's local-NVMe families are ClickHouse's canonical deployment target, and S3 disk-tiering is its most exercised cold-storage path.
2. **Key management for provable erasure.** The crypto-shred design (slide 14) needs per-user keys with an auditable deletion event. KMS with CloudTrail-logged key deletion supports this directly.
3. **Team and partner depth.** Defensible under live questioning, staffable. A legitimate pre-sale criterion, not a tiebreaker to be embarrassed about.

**The runner-up is closer than most decks admit, and here is exactly what flips it:**

> **If you commit to a managed FHIR store as the system of record in phase 2, Azure wins.** Azure Health Data Services' **MedTech connector exists specifically to ingest wearable/IoMT device data into FHIR** — that is this product's core data path. Combined with the EU Data Boundary being the crispest formal residency commitment of the three, the case for Azure becomes strong. Our recommendation assumes FHIR *alignment* (slide 4), not a FHIR *server*. If that assumption changes, so does ours.

GCP is not eliminated on capability — mature health API, best confidential-computing story — but loses on EU region breadth, and its strongest differentiator, BigQuery, is irrelevant to a ClickHouse-based architecture.

**What could override all of this and that we don't know yet:** an existing enterprise agreement (especially Microsoft) changes the cost calculus materially; your platform team's existing cloud skills — self-hosted ClickHouse raises that bar; what you're migrating from. These are on slide 20.

**Speaker notes:** This is the graded question from your brief — take the follow-up questions here rather than rushing past. If asked "so why not just ask about FHIR now and decide" — we are asking; it's slide 20, item 4, deliberately framed as the single question most likely to move this recommendation.

---

## 13. Data platform — Postgres for state, ClickHouse for events

> **Postgres stores things that change. ClickHouse stores things that happened.**

| Postgres — state | ClickHouse — events |
|---|---|
| Account, profile, consent grants | Health telemetry samples (HR, steps, sleep) |
| PHI-access audit log (monthly partitions) | Rollups, workout session series |
| Loyalty tier, social graph, device connections | Product analytics, provider-call telemetry |
| Vendor OAuth tokens (envelope-encrypted) | Population-insight aggregates |

- Borderline case named rather than hidden: **body measurements live in both, correctly** — full history in ClickHouse, latest value denormalised onto the Postgres profile for the recommendation hot path (a point lookup).
- Volume, corrected: naive 1 Hz heart-rate assumptions are wrong for this product — HealthKit samples roughly every 5 minutes at rest, near-continuously only during workouts. Realistic estimate: ~3–5k samples/day/active user, ~15B/day at 3M wearable-connected users, compressing to 5–16 TB/year in ClickHouse. Large, tractable, not the number a naive estimate produces.
- **Two-plane separation, two AWS accounts:** PHI account (Aurora + ClickHouse #1, health telemetry) and Analytics account (ClickHouse #2, pseudonymous product events). CH#2 needs a wide, growing audience — analysts, PMs, BI. **CH#1 needs almost none.** Access that broad next to data that sensitive is where grants drift; a leaked analyst credential or a wildcard policy cannot cross an account boundary the way it can cross a permission boundary within one account.

**Speaker notes:** The test for whether this separation is real: "health data lives in a separate account analysts have no path into" survives follow-up questioning; "health data is separated by database permissions" does not. This is deliberately not built (Bucket C, slide 18) but the account topology is a design decision we want validated before build starts, not after.

---

## 14. Security controls — provable erasure for a company that just settled this exact claim

- TLS 1.2+ everywhere including service-to-service, mTLS between tiers. KMS CMK at rest, **per-user envelope keys** for health samples. CloudTrail + an application-level PHI-access audit log. No PHI in application logs — `request_id` propagated through gRPC metadata for tracing without identifiers.
- **Erasure: crypto-shredding.** Per-user data keys in KMS; erasure destroys the key, ciphertext remains and becomes permanently unrecoverable. KMS key deletion is logged in CloudTrail — the erasure event is **provable**, which is what a company that just settled a data-loss claim actually needs. One mechanism satisfies encryption-at-rest and right-to-erasure together.
- **Durability, the other half of the same lawsuit lens:** Aurora Multi-AZ synchronous standby (RPO≈0) + PITR to any second; ClickHouse `ReplicatedMergeTree` across AZs; S3 versioning + Object Lock (defends against accidental *and* malicious deletion — the actual mechanism of most incidents); cross-region backup copies in the same jurisdiction; **a quarterly restore drill with measured RTO/RPO and a written runbook.**
- That last control costs the least and matters most: "we test restores on a schedule, here's the runbook" lands harder with someone who just wrote a settlement cheque than a third region on a diagram.

**Speaker notes:** This slide is designed, not built (Bucket C) — say so plainly if asked, then pivot to why it's still the right answer to lead with: it's the direct rebuttal to the lawsuit, and getting the mechanism right (crypto-shred + provable deletion) matters more at this stage than having it running.

---

## 15. GDPR — data minimisation you can watch happen, and the conflict we're not hiding

- **Data minimisation, executable, not a slide bullet.** Service 1 doesn't require birth date; Service 2 does. `Requires()` turns that into a routing rule — the aggregator skips a provider whose required fields are absent. A user who declines to supply DOB gets Service 1 results only, and the system tells them why. You'll watch this happen in the demo in about ten seconds.
- Explicit consent per purpose for Art. 9 data; right to erasure via crypto-shredding (slide 14); residency via per-region cells (next slide); a DPIA is required — profiling at scale triggers Art. 35.
- **The awkward case, named on purpose: the consent/PHI-access audit log is *not* erasable** — 6-year legal-basis retention, append-only, in Postgres. This makes the erasure-versus-retention conflict concrete instead of hand-waved, and it's exactly why "were you a covered entity, and where does erasure yield to retention" is the first regulatory question on slide 20.
- Sharpest landmine in your brief: "meet friends" over Art. 9 health data needs granular, revocable, per-audience consent, and share payloads must carry no health values by default. Designed only — flagged here so it isn't discovered at social-feature build time.

**Speaker notes:** This is the moment to preview the demo: "in about five minutes you'll watch a provider drop out live when we clear a birth-date field, rendered as an informational banner, not an error — that's this slide, running."

---

## 16. Per-region cells, and analytics as four workloads, not one

- Your brief states the deployment shape directly: pilot in a few regions, then move globally if successful. That's **cell-based deployment**, not one global system replicated — each region runs its own Postgres, own ClickHouse, own residency boundary, users pinned home.
- One choice satisfies three requirements: GDPR residency falls out for free; the phased rollout *is* the deployment model, not a migration problem later; a compromise or outage in one region can't reach another. Blast-radius containment is a stronger answer to a breach-flavoured lawsuit than keeping more copies.
- **Analytics is four workloads, and your brief states only one of them:**

| Workload | What it is | Store |
|---|---|---|
| Health telemetry | Sensor samples powering charts + recommendation inputs | ClickHouse #1 (PHI) |
| **Product analytics** | Screens, funnels, tier conversion — the brief's stated bullet | ClickHouse #2 |
| Operational/APM | Latency, error rates, per-provider SLOs | CloudWatch + OTel |
| Population insights | Aggregate mining → "state-of-the-art tips" | ClickHouse #1, controlled export |

- **Population insights hides inside your own loyalty paragraph** — Platinum's "earlier access to the best insights" is literally staged release of population-analytics output. That workload sits on PHI, so it needs aggregate-only export with k-anonymity thresholds. No third-party analytics SDK — several EU DPAs found Google Analytics unlawful for EU personal data post-Schrems II; self-hosted, EU-resident, pseudonymous instead.

**Speaker notes:** Naming workloads 3 and 4 explicitly, when your brief only states #2, is meant to demonstrate we read the brief the way an engineer reads a brief, not the way a summariser does. Good moment for the architect to jump in if they disagree with the ClickHouse split.

---

## 17. Client architecture, and environments/CI-CD as they actually stand

- **Web** — Closure Compiler + Library, ADVANCED mode. No charting dependency (`goog.graphics` is fully deprecated) — raw `<canvas>` for the live vitals strip, raw SVG for stats charts, `Pchip1` monotone interpolation so smoothing can't render negative step counts. Satisfies your "no 3rd-party components" line as a side effect, not a workaround.
- **iOS** — Objective-C, UIKit, iOS 15+, no Swift/SwiftUI, matching your existing monorepo conventions. gRPC directly to app-server with a bearer token. HealthKit prefill (height/weight/DOB) built and verified; never fails loudly — an unavailable value just leaves the field open for manual entry.
- **Android** — Java, XML Views + AppCompat, API 24+, no Kotlin/Compose. Same gRPC + bearer-token contract. Health Connect prefill is **SDK-availability detection only** — the real read is cut, for two independent reasons: `connect-client`'s read APIs are Kotlin-suspend-only with no verified pure-Java surface, and separately, Health Connect has no birth-date record type at all, so DOB will always be manual entry on Android regardless.
- All three render `ok`/`skipped`/`degraded` provider states with distinct styling, verified on a live six-row response from both real vendors. Fault injection is **deliberately web-only** — a presenter tool for a page that's never installed on a device; shipping a "break this backend provider" switch inside a customer-held mobile binary is a liability, not a convenience.
- **Environments/CI-CD, honestly:** dev → staging → production per region, staging synthetic-data-only, is *designed*. A GitHub Actions pipeline (lint, test, build, deploy) is *designed but not built* — absent from what shipped.

**Speaker notes:** If asked about test coverage: Go has 44 race-clean tests across the aggregator/domain/providers/ranking packages; web-proxy has supertest coverage; the web client itself has none (flagged, not hidden, on slide 18). Both mobile clients have unit tests specifically pinning the skipped-before-degraded branch order — each was proven to catch a real regression by deliberately reversing the branch once and watching the test fail.

---

## 18. Honest status — what we built vs. what we designed vs. what isn't done

We are not going to let you find this gap yourselves.

| Built (code, tested, deployed) | Designed only (document, not code) | Not done |
|---|---|---|
| Go gRPC core — fan-out, ranking, dedupe, error classification | Data platform (Postgres/ClickHouse schemas, retention tiers, crypto-shred) | SSE vitals strip |
| REST façade (web-proxy) | Compliance controls (audit log, plane separation, DPIA) | Database DDL |
| Closure web client, with fault injection | Device framework beyond manual entry (HealthKit/Health Connect prefill are built; vendor-cloud OAuth, BLE GATT adapters are not) | Partner OpenAPI spec |
| nginx edge tier (TLS, gRPC routing) | Loyalty tiers, social graph, reseller/gym integrations | CI/CD pipeline |
| iOS client (Objective-C/UIKit) | | |
| Android client (Java/AppCompat) | | |
| Real vendor integration — both services, corrected contracts, dedupe, score clamping | | |

- **A code review ran against this branch and found real problems**, which we fixed rather than presented around: the public gRPC edge was reachable without authentication with reflection exposed; neither mobile client sent a bearer token; iOS could have its TLS/host silently repointed via a debug-only override left live in Release. All three are closed — verified with `strings`/`nm` against the actual Release binaries, not just a code read.
- **The review also flagged that this deck, the demo script, and live-coding prep didn't exist yet, while an Android client (an optional differentiator) had been built.** That finding is what produced the three documents you're looking at right now, plus this table.

**Speaker notes:** Do not skip this slide or rush it. It is the single highest-trust move in the deck — a vendor who shows you the gap unprompted is more credible than one with a spotless-looking deck. Land on: "everything in the middle and right columns is a sequencing decision, not a hidden failure — we can walk through why each one is designed-not-built if useful."

---

## 19. Live demo

What you're about to see, in order: enter measurements → merged, ranked, deduplicated recommendations from both real vendors, with provenance visible per row. Clear the birth date → Service 2 is skipped, results still render, an informational banner explains why — GDPR data minimisation, executable. Tick the fault toggle → a provider dies mid-session, partial results still render, the banner degrades within about two seconds. Optionally, the same backend, the same session, viewed from an iOS or Android client over gRPC.

Full run-of-show, including the warming procedure, is in `docs/demo-script.md`.

**Speaker notes:** Hand off to whoever is driving. Confirm the warm-up (three calls hitting both providers) has already happened before this slide — it should have run silently during the cloud-recommendation or security discussion, not in front of the audience.

---

## 20. Our questions for you

Ending on questions turns this from an examination into a working session.

1. **How did the endpoint links and response-shape documentation in your own brief go stale relative to what's actually deployed?** We found three separate mismatches (slide 6) purely by testing against your live services. Worth knowing whether other internal docs carry the same drift.
2. **Are you a HIPAA covered entity or business associate, or is this consumer wellness under FTC HBNR and GDPR Art. 9?** Changes retention obligations and BAA requirements directly.
3. **Was the settled suit a disclosure incident or a durability incident?** The two readings push in opposite directions — one says hold less and encrypt harder, the other says keep more copies. It determines where the security budget actually goes.
4. **What analyses might you want to run retrospectively on raw health data?** This sets raw-sample retention far better than "how long do you keep data," and it forces a stated purpose, which Art. 5(1)(b) requires anyway.
5. **Do you intend a managed FHIR store as a system of record, or is FHIR alignment sufficient?** This is the single question that would move our cloud recommendation from AWS to Azure (slide 12).
6. Do you hold an existing enterprise agreement with any cloud provider — particularly Microsoft? It can outweigh every technical criterion in our comparison.
7. Who onboards a new recommendation provider — you, us, or the provider? Decides whether the provider seam stays in-process or goes out-of-process.
8. When phone and watch both report steps, which wins? Real, common, almost always discovered late.

**Speaker notes:** If time is short, prioritise 3, 4, and 5 — they change the most and are the ones a generic vendor deck would never think to ask.
