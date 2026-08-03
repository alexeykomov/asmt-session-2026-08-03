<!-- .slide: class="title-slide" -->

# FunWithActivity

## Architecture

**Pre-sale technical session** · PMs, architect, tech lead

Note: ~17 slides, then a five-minute live demo, then we take live-coding requests. Name the format up front. Several slides end in a question we are asking *them* — that framing matters for the last slide.

---

## The brief, the five forces, and the lawsuit

A health/activity recommender: connect any consumer health hardware, normalise what it collects, return behavioural recommendations. Loyalty tiers, a social layer, resellers and gyms on the roadmap.

1. **Extensibility** — "more services/devices are to be added soon"
2. **Scale** — aggressive growth, global rollout after a regional pilot
3. **Data sensitivity** — health data, GDPR, a social layer on top of it
4. **Reliability** — hardware and vendor integrations you don't control
5. **A cloud recommendation** — reasoned, not asserted

> **You settled a lawsuit alleging user data loss.** We are not treating that as background. The erasure mechanism, the durability controls, the plane separation and the per-region cells are all legible against that fact — and we say so as we go rather than making you connect the dots.

You asked us to (a) design this to be genuinely extensible and (b) recommend a cloud provider with reasoning. **Both are graded questions.** We'll show working code, not just slides — a live gRPC backend and three clients, all talking to your real vendor services.

Note: Deliberately blunt. Health companies get pitched generic "secure, scalable, compliant" decks constantly; naming the lawsuit up front signals we read the brief as engineers, not as a sales team. Pause here before moving to architecture.

---

## Your four answers, and what they settle

We asked four questions. The answers moved the architecture more than the brief did — and two of them together invalidate our own PoC's central mechanic, which we would rather say out loud than have you find.

| We asked | You answered |
|---|---|
| Was the lawsuit a breach or a durability failure? | **Both concerns are valid** |
| Expected load, average and peak? | **500 / 2000 RPS** |
| Would an API standard suit new services and devices? | **Limited or no control over third-party APIs** |
| Do the tiers imply payment? | **Yes — paid subscriptions are key** |

**2000 RPS peak makes per-request fan-out impossible.** Two providers at peak is 4,000 outbound third-party calls per second, over APIs you cannot renegotiate, from a vendor we have measured failing about one call in three. So the request path cannot call vendors in production. **Persistence is not a feature we would add later — it is the production read path.**

**No control over their APIs makes adapters permanent** — not a transitional step toward an interface we define. The open question becomes *who writes the adapter*.

**Paid tiers make routing entitlement-aware** — same seam, one more input.

Note: This is the slide that proves we did arithmetic rather than pattern-matching. The 2000 RPS figure turns the rest of the deck from preference into derivation. Expect "so your demo doesn't scale?" — answer yes, deliberately: the brief asked for input collected in the UI; the demo shows the merge, ranking and degradation logic, and what moves is the trigger for it. Lands better as a finding than an apology.

---

<!-- .slide: class="diagram-slide" -->

## High-level architecture — what we built

<img src="img/01-poc-request-path.svg" alt="PoC request path">

Note: Browsers go through web-proxy over REST; native clients speak gRPC straight to the edge. The organising rule is on the next slide — point back to it whenever anyone asks "why gRPC here and REST there".

---

## "Extensible" is not one seam — it is five

<img class="seams" src="img/03-extension-seams.svg" alt="The five extension seams">

**The organising rule: gRPC is the boundary for things we control on both ends. Adapters and REST are the boundary for things we don't.** Browsers can't speak gRPC without a proxy; resellers won't integrate over gRPC; your vendors speak whatever HTTP/JSON they speak.

Your brief names seams 1 and 2. Seam 3 is implied by "expanding aggressively". Seams 4 and 5 are the ones a generic deck misses entirely.

Note: This is the direct answer to graded question (a). Seams 4 and 5 share a mechanism — the same proto — and differ on who can break whom: a shipped mobile binary cannot be recalled, so that contract is append-only forever; an internal service is a coordinated release. If the architect asks "how do you decide gRPC vs REST vs adapter", the rule above is the one-sentence answer.

---

## Any hardware on the market — four adapter classes

"Work with any physical hardware" is not "build one integration per device" — that is an infinite backlog.

| Class | Mechanism | Covers |
|---|---|---|
| Platform health stores | HealthKit, Health Connect | Apple Watch + everything writing to the store — the large majority |
| Vendor cloud APIs | OAuth2 + webhooks | Fitbit, Garmin, Oura, Withings, Polar |
| BLE GATT standard profiles | Heart Rate, Weight Scale, Cycling Speed | Unbranded hardware direct to phone |
| Manual entry | UI | Everything else — and today's PoC path |

- Every adapter normalises into a model **aligned to HL7 FHIR `Observation`** — code, subject, effective time, UCUM-unit value, device reference. FHIR-*aligned*, not a FHIR *server*, for the pilot.
- All three hyperscalers offer a managed FHIR store, so this does not lock us to one vendor — and your reseller/gym/insurer roadmap already speaks FHIR.
- **Adding a device is registering an adapter, not changing the core.**

Note: The worked example for extensibility — walk through what adding a Garmin OAuth adapter actually touches: implement DeviceAdapter, register a capability set, done. If asked why not a full FHIR server now: alignment is the cheaper, reversible bet, and adopting a managed FHIR service is a phase-2 decision the model is already compatible with. This seeds the Azure condition later.

---

## What we found testing your live services

Four findings we are handing back, not complaining about. We built to your written brief, then hit your live endpoints.

| | Your brief | What is actually deployed |
|---|---|---|
| Envelope | Inner payload only | Every response wrapped in a **Lambda proxy envelope** — `body` is a JSON *string*, parsed twice |
| Service 2 success | `{"recommendations": [...]}` | A **bare array** — the documented key does not exist |
| Provider errors | Implied HTTP status | Arrive over **HTTP 200**, with a `statusCode` inside the body that contradicts the transport status |
| Schema violations | Undocumented | A **third** shape — FastAPI's `{"detail": [...]}` |

- **Your error codes are not a classifiable signal.** Documented: `errorCode 39` means invalid token. We ran 25 invalid-token calls: code 39 never recurred — we got 28 different codes, each with a different canned message, always at `statusCode 503`. So the adapter classifies on transport facts, not vendor codes.
- **Your responses contain duplicates,** measured not theorised: `"Don't eat carbs!"` three times in one Service 1 call; `"Go for a physical check up"` from both providers in one session. Dedupe shipped as a real component, not a no-op.

Note: Land as evidence, not accusation — "we verified against your live endpoint and your own OpenAPI document; here is the diff." The adapter built strictly to the brief would have silently returned zero Service 2 recommendations on every real call. The ask: a stable error code per failure class, or an explicit field we can classify on.

---

## Resilience, cold start, and where gRPC broke

- Fan-out via `sync.WaitGroup`, **not** `errgroup` — errgroup cancels siblings on first error, and partial results *are* the product. Per-provider `context.WithTimeout`, per-provider panic recovery, per-provider status whatever happens.
- Three outcomes stay distinct: **ok** / **skipped** (not called — required data absent) / **degraded** (called, failed). Reading `error` before `skipped` reports a privacy decision as an outage — it has caused four defects here, and all three clients now pin the order with tests.
- **Cold start is real and measured.** Each vendor Lambda warms independently; the first call after idle misses the 2s timeout entirely, a warm call answers in 60–120 ms. It takes ~3 calls before both are reliably warm — which is why the demo has a warming procedure, and why we are telling you now rather than letting you find it live.
- **gRPC does not survive DigitalOcean App Platform's ingress** — it proxies HTTP/1.1 to containers; our server speaks h2c. Verified with `grpcurl`. A limitation of one PaaS, not of the architecture: ALB with a gRPC target group, Cloud Run and Container Apps all speak HTTP/2 natively. It is why an nginx edge exists — and why **PoC hosting is not the production target.**

Note: If asked "why not just fix DigitalOcean" — you can't, it is ingress behaviour, not configuration. If asked why not move PoC hosting to AWS now — the PoC carries no real user data, so the cost is an edge-tier workaround, not a redesign.

---

## Cloud — criteria, and the head-to-head

**The finding that comes first: the architecture is deliberately cloud-neutral, so this decision is reversible.** Go services in containers, PostgreSQL, self-hosted ClickHouse, object storage — every component has a direct equivalent on all three. No managed proprietary database, no serverless lock-in.

| | AWS | Azure | GCP |
|---|---|---|---|
| HIPAA / BAA | Broadest catalogue | Strong, simplest with an enterprise agreement | Solid |
| EU residency | `eu-central-1` + announced European Sovereign Cloud | **Clearest formal commitment** — EU Data Boundary | Sovereign Controls; fewer regions |
| Managed FHIR | HealthLake | **Health Data Services + MedTech connector** | Cloud Healthcare API |
| ClickHouse hosting | **Strongest** — `i`-family NVMe, S3 the most battle-tested cold tier | AKS + `Lsv3`, less proven | GKE good, local SSD good |
| Distinctive analytics | — | — | BigQuery — **but we are not using it** |

Criteria, in order: HIPAA/BAA · EU residency · managed FHIR · key management for provable erasure · ClickHouse operational fit · region breadth · cost shape · exit cost · team depth.

Note: Say the cloud-neutrality point BEFORE naming a provider — it changes how the recommendation lands. This slide is data; the verdict is next.

---

## Cloud — AWS, and the condition that flips it to Azure

**Recommendation: AWS** — on three criteria, none of them "AWS is biggest":

1. **ClickHouse operational fit.** The largest self-hosted component in the platform. AWS local-NVMe families are ClickHouse's canonical deployment target; S3 disk-tiering is its most exercised cold path.
2. **Key management for provable erasure.** Crypto-shredding needs per-user keys with an auditable deletion event. KMS with CloudTrail-logged key deletion supports this directly.
3. **Team and partner depth.** Defensible under live questioning, staffable. A legitimate pre-sale criterion.

> **If you commit to a managed FHIR store as system of record in phase 2, Azure wins.** Azure Health Data Services' **MedTech connector exists specifically to ingest wearable/IoMT data into FHIR** — that is this product's core data path. With the EU Data Boundary being the crispest residency commitment of the three, the case becomes strong. Our recommendation assumes FHIR *alignment*, not a FHIR *server*. If that assumption changes, so does ours.

GCP is not eliminated on capability, but loses on EU region breadth, and its strongest differentiator — BigQuery — is irrelevant to a ClickHouse architecture.

**What could override all of this and we don't know yet:** an existing enterprise agreement, especially Microsoft.

Note: This is graded question (b) — take follow-ups here rather than rushing past. If asked "why not just ask about FHIR now and decide" — we are asking; it is on the questions slide, framed as the single question most likely to move this recommendation.

---

<!-- .slide: class="diagram-slide" -->

## Target production architecture

<img src="img/04-production.svg" alt="Target production architecture">

Note: Four things to land, in order. One: everything before this was the PoC — telemetry arrives continuously rather than typed into a form, generation is a background refresh behind a cache and circuit breaker, and the read path serves 2000 RPS entirely from our own store, never calling a vendor inline. Two: there are two vendor seams pointing in opposite directions — inbound connectors pull user data in from third-party health APIs and normalise it into the device-sample schema, outbound adapters call recommendation services; one is a PHI data source, the other a compute dependency. Three: the edge, web-proxy and gRPC tiers survive from the PoC unchanged, and so does the Requires() gate — only its trigger moves, from an inline call to a background one. Four: the data-minimisation gate and the entitlement check are drawn inside the processes that own them because neither is a service; drawing them as separate boxes would put network hops on the diagram that the design does not have. If the architect asks where compliance lives on this diagram, section 4a of docs/architecture-diagrams.md maps every control to the obligation it discharges — and, deliberately, lists what an architecture diagram cannot show at all: BAAs, the DPIA, breach runbooks, retention schedules.

---

## Postgres stores things that change. ClickHouse stores things that happened.

| Postgres — state | ClickHouse — events |
|---|---|
| Account, profile, consent grants | Health telemetry samples (HR, steps, sleep) |
| PHI-access audit log (monthly partitions) | Rollups, workout session series |
| Loyalty tier, social graph, device connections | Product analytics, provider-call telemetry |
| Vendor OAuth tokens (envelope-encrypted) | Population-insight aggregates |

- Borderline case named rather than hidden: **body measurements live in both, correctly** — full history in ClickHouse, latest value denormalised onto the Postgres profile for the recommendation hot path.
- **Volume, corrected.** Naive 1 Hz assumptions are wrong for this product: HealthKit samples roughly every 5 minutes at rest, near-continuously only during workouts. Realistically ~3–5k samples/day/active user → ~15B/day at 3M connected users → 5–16 TB/year compressed. Large, tractable, not the number a naive estimate produces.
- **Two ClickHouse deployments, and the reason is access, not volume.** CH #1 holds PHI and needs almost no human access. CH #2 holds pseudonymous product events and needs a wide, growing audience — analysts, PMs, BI. Access that broad next to data that sensitive is where grants drift. Separate accounts, not separate permissions.

Note: The test for whether the separation is real: "health data lives in a separate account analysts have no path into" survives follow-up questioning; "separated by database permissions" does not. Designed, not built — but the account topology is a decision we want validated before build starts, not after.

---

## Security — provable erasure, and durability as the other half

- TLS 1.2+ everywhere including service-to-service, mTLS between tiers. KMS CMK at rest, **per-user envelope keys** for health samples. No PHI in application logs — `request_id` through gRPC metadata for tracing without identifiers.
- **Erasure: crypto-shredding, because ClickHouse is bad at deleting.** `MergeTree` parts are immutable, so a delete is a mutation that rewrites every part holding a matching row — and one user's samples end up scattered across nearly all of them. Dropping a whole partition is cheap; erasing one user is not. That is backwards from what Art. 17 asks. So erasure destroys a key instead: the ciphertext stays and becomes permanently unreadable, and the event is **provable** from an audit log rather than asserted. It also reaches what deletion cannot — every retained backup, snapshot and replica, in one operation.
- **What is shredded is the identity linkage, not the samples.** Per-user-encrypted columns are high-entropy, so columnar compression collapses — and the volume estimates depend on it — while population-insight queries aggregate *across* users, which per-user keys make impossible. Telemetry lands under a per-user pseudonym; the pseudonym-to-identity mapping is encrypted in Postgres; erasure destroys the mapping and partition TTL ages the orphaned rows out. Whether those orphans are then *anonymous* under Art. 4(5) or merely pseudonymous is a question for your DPO — health time series are notoriously re-identifiable, and we are not going to assume the favourable reading.
- **Durability, the other reading of the same lawsuit:** Aurora Multi-AZ synchronous standby (RPO≈0) + PITR; ClickHouse `ReplicatedMergeTree` across AZs; S3 versioning + Object Lock — which defends against accidental *and* malicious deletion, the actual mechanism of most incidents; **a quarterly restore drill with measured RTO/RPO and a written runbook.**
- That last control costs the least and matters most: "we test restores on a schedule, here is the runbook" lands harder with someone who just wrote a settlement cheque than a third region on a diagram.

Note: Designed, not built — say so plainly if asked, then pivot to why it is still the right thing to lead with: it is the direct rebuttal to the lawsuit, and getting the mechanism right matters more at this stage than having it running. "Both concerns are valid" means two separate answers; this slide gives both rather than blurring them.

---

## GDPR — minimisation you can watch happen, and the conflict we are not hiding

- **Data minimisation, executable, not a slide bullet.** Service 1 does not require birth date; Service 2 does. `Requires()` turns that into a routing rule — the aggregator **skips** a provider whose required fields are absent rather than calling it with placeholder data. A user who declines DOB gets Service 1 results only, and the system tells them why. **You will watch this happen in the demo in about ten seconds.**
- Explicit consent per purpose for Art. 9 data; erasure via crypto-shredding; residency via per-region cells; a DPIA is required — profiling at scale triggers Art. 35.
- **The awkward case, named on purpose: the consent/PHI-access audit log is _not_ erasable** — six-year legal-basis retention, append-only. That is a real conflict with Art. 17, and where erasure yields to retention is your call, not our assumption.
- **Sharpest landmine in your brief:** "meet friends" over Art. 9 health data needs granular, revocable, per-audience consent, and share payloads must carry no health values by default. Designed only — flagged so it is not discovered at social-feature build time.

Note: Preview the demo here: "in about five minutes you will watch a provider drop out live when we clear a birth-date field, rendered as an informational banner, not an error — that is this slide, running." The full control-to-obligation mapping, including what an architecture diagram cannot show, is section 4a of docs/architecture-diagrams.md.

---

## Per-region cells, and analytics as four workloads

- Your brief states the deployment shape directly: pilot in a few regions, then global. That is **cell-based deployment** — each region its own Postgres, own ClickHouse, own residency boundary, users pinned home.
- **One choice satisfies three requirements:** GDPR residency falls out for free; the phased rollout *is* the deployment model rather than a migration problem later; a compromise or outage in one region cannot reach another. Blast-radius containment is a stronger answer to a breach-flavoured lawsuit than keeping more copies.

| Workload | What it is | Store |
|---|---|---|
| Health telemetry | Sensor samples powering charts + recommendation inputs | ClickHouse #1 (PHI) |
| **Product analytics** | Screens, funnels, tier conversion — *the brief's stated bullet* | ClickHouse #2 |
| Operational / APM | Latency, error rates, per-provider SLOs | Metrics + OTel |
| Population insights | Aggregate mining → "state-of-the-art tips" | ClickHouse #1, controlled export |

**Population insights hides inside your own loyalty paragraph** — Platinum's "earlier access to the best insights" is staged release of population-analytics output. That workload sits on PHI, so it needs aggregate-only export with k-anonymity thresholds. No third-party analytics SDK: several EU DPAs found Google Analytics unlawful for EU personal data post-Schrems II.

Note: Naming workloads 3 and 4, when the brief states only #2, demonstrates we read the brief the way an engineer reads a brief, not the way a summariser does. Good moment for the architect to push back on the ClickHouse split.

---

## Honest status — built vs. designed vs. not done

We are not going to let you find this gap yourselves.

| Built — code, tested, deployed | Designed only | Not done |
|---|---|---|
| Go gRPC core — fan-out, ranking, dedupe, error classification | Data platform schemas, retention tiers, crypto-shred | SSE vitals strip |
| REST façade (web-proxy) | Compliance controls — audit log, plane separation, DPIA | Database DDL |
| Closure web client, ADVANCED compilation | Device framework beyond manual entry (HealthKit/Health Connect prefill *are* built) | Partner OpenAPI spec |
| nginx edge tier — TLS, gRPC routing | Loyalty tiers, social graph, reseller integrations | CI/CD pipeline |
| iOS (Obj-C/UIKit) and Android (Java/AppCompat) clients | | |
| Real vendor integration — both services, corrected contracts | | |

- **A code review ran against this branch and found real problems**, which we fixed rather than presented around: the public gRPC edge was reachable **without authentication**, with reflection exposed; neither mobile client sent a bearer token; iOS could have its TLS/host silently repointed by a debug override left live in Release. All three closed — verified with `strings`/`nm` against the actual Release binaries, not a code read.
- **The same review flagged that this deck and the demo script did not exist yet, while an optional Android client had been built.** That finding produced the documents you are looking at.

Note: Do not skip or rush this slide. It is the single highest-trust move in the deck — a vendor who shows you the gap unprompted is more credible than one with a spotless-looking deck. Land on: everything in the middle and right columns is a sequencing decision, not a hidden failure.

---

## Live demo

In order:

1. **Enter measurements** → merged, ranked, deduplicated recommendations from both real vendors, provenance visible per row.
2. **Clear the birth date** → Service 2 is **skipped**, results still render, an informational banner explains why. GDPR data minimisation, executable.
3. **Tick the fault toggle** → a provider dies mid-session, partial results still render, the banner degrades within about two seconds.
4. Optionally — the same backend, the same session, from the iOS or Android client over gRPC.

Note: Hand off to whoever is driving. Confirm the warm-up — three calls hitting both providers — has already happened, silently, during the cloud or security discussion. Not in front of the audience. Full run-of-show is in docs/demo-script-1.2.0.md.

---

## Our questions for you

Ending on questions turns this from an examination into a working session.

1. **How did your own brief's endpoint and response-shape documentation go stale** relative to what is deployed? We found four mismatches purely by testing. Worth knowing whether other internal docs carry the same drift.
2. **Are you a HIPAA covered entity or business associate, or is this consumer wellness** under FTC HBNR and GDPR Art. 9? Changes retention obligations and BAA requirements directly.
3. **Was the settled suit a disclosure incident or a durability incident?** The two readings push in opposite directions — hold less and encrypt harder, versus keep more copies. It decides where the security budget goes.
4. **What analyses might you want to run retrospectively on raw health data?** This sets raw-sample retention far better than "how long do you keep data", and forces a stated purpose, which Art. 5(1)(b) requires anyway.
5. **Managed FHIR store as system of record, or is FHIR alignment sufficient?** The single question that would move our cloud recommendation from AWS to Azure.
6. **Do you hold an enterprise agreement with any cloud provider** — particularly Microsoft?
7. **Who onboards a new recommendation provider** — you, us, or the provider? Decides whether the provider seam stays in-process.
8. **When phone and watch both report steps, which wins?** Real, common, almost always discovered late.

Note: If time is short, prioritise 3, 4 and 5 — they change the most and are the ones a generic vendor deck would never think to ask.

---

<!-- .slide: class="title-slide" -->

# Thank you

**Questions, and live-coding requests, welcome.**

Note: Rehearsed live-coding asks: change ranker weights via env var without a rebuild; add a third provider; flip a provider's Requires() set.
