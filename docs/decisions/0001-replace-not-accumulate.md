# 0001 — Recommendations replace on each request; they do not accumulate

**Status:** accepted · 2026-08-03
**Applies to:** web client, iOS client, Android client

## Decision

Every request renders **only that response's** recommendations. The previous
result set is discarded. No client merges results across requests.

This is already the behaviour in all three clients, and it is deliberate:

| Client | Mechanism |
|---|---|
| Web | `renderTable_` re-renders the Soy template into `#recs-table-mount`, replacing its contents |
| Android | `RecommendationAdapter`: `items.clear(); items.addAll(newItems); notifyDataSetChanged()` |
| iOS | A fresh `FWAResultsViewController` per submission |

## Why — the demo beats depend on the list shrinking

Two of the three demo beats are *reductions* in the result set:

- **Data minimisation** — clear the birth date, `service2` is skipped, fewer rows
- **Resilience** — trip the fault toggle, a provider fails, fewer rows

If results accumulated, the table would **never shrink**. Rows from the previous
full response would remain on screen while the banner announced that a provider
was unavailable or skipped — the screen would contradict itself, and the two
most important things the PoC demonstrates would become invisible.

This is the decisive reason. The rest reinforce it.

## Supporting reasons

**The banner describes the current response.** `statuses[]` is per-request.
Accumulated rows from an earlier call would sit under a banner that does not
describe them.

**The vendors are non-deterministic.** The same request returns a different draw
each time (verified: repeated identical calls yield different sets with
overlapping titles). Accumulation would grow an ever-longer list of near-variants
rather than converging on anything.

**The demo warms up before anyone is watching.** The documented procedure makes
~3 calls to wake the cold-start Lambdas. Under accumulation the presenter would
reach the first slide with a screen already full of results.

**Scores are ranked within a response.** `WeightedNormalizedRanker` orders one
response's merged set. Blending sets ranked at different moments produces an
order that is not meaningful, even though the 0..1 normalisation makes the
numbers superficially comparable.

## Consequence to handle verbally, not in code

Submitting twice with identical input returns **different** recommendations,
because the vendor draws are random. A technical audience will notice. Answer it
directly rather than hiding it:

> "Their service returns a different draw on each call — you can see our dedupe
> collapsing the overlap. In production we'd persist these rather than re-query
> per interaction."

## What this decision is *not*

It is not a claim about the real product. A shipped FunWithActivity would not
have a submit button at all: recommendations would be generated from ingested
telemetry, persisted, and presented as an evolving set with a lifecycle (new /
seen / acted-on / expired) feeding the ranker calibration loop described in the
design specification. The form-and-submit model exists because the brief says
*"for POC purposes, all required data could be asked in application UI"*.

Accumulation is the wrong shape for the PoC **and** the wrong question for the
product — the product's answer is persistence, not client-side merging.

## Revisit if

- The demo stops relying on the list shrinking to show skipped/degraded states
- Recommendations become persisted server-side, at which point the client shows
  a stored set rather than a per-request result and this decision is superseded

## Follow-up

Add a one-line comment at each of the three render sites pointing here, so the
behaviour is not "corrected" into accumulation by someone who has not read this.
