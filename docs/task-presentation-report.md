# Presentation deliverables — report

Three artifacts written against the approved design spec, the mobile/integration docs, the code-review verdict, and the build/verification reports — the presentation layer for work that was otherwise already built.

## Status

Done. All three deliverables written and committed separately, plus this report.

## Commits

- `edd20cb` — `docs/deck/funwithactivity-architecture.md`
- `30916b3` — `docs/demo-script.md`
- `bd67905` — `docs/live-coding-prep.md` (rehearsal material; not included in this repo)

## Slide count

20 slides (`##` headers 1–20), each with speaker notes.

## Concerns

- The deployed demo app's public DigitalOcean URL is not recorded anywhere in the repo (only the region and auto-generated-domain mechanism are). The demo script's warm-up section gives a `<your-demo-app>.ondigitalocean.app` placeholder for the through-the-app warm-up path, plus a domain-independent fallback that curls the two vendor Lambda URLs directly — the presenter must fill in the real URL on the day.
- The deck states plainly (slide 18) that database DDL, partner OpenAPI, and CI/CD remain undone, per the code review's CR-008 finding — this presentation work does not close those gaps, only presents them honestly. If the customer expects those artifacts delivered "the day before," that gap is still open and belongs on someone's list before this ships.
- The demo script's stub-fallback fault-toggle quirk (no-ops on the very first submit of a stub session) is real and traced to a specific commit (`ec4f5fa`), but is a narrow edge case that only matters if the presenter ends up on the `USE_STUB_PROVIDERS=true` fallback *and* skips a warm-up submit first — worth a dry run before the actual session to confirm it behaves as documented.
- Live-coding rebuild times (`~0.5s` app-server, `~5–5.5s` web-client) were measured on this development machine just now, not on whatever machine will actually be used on presentation day — treat as an estimate, re-measure on the presenting hardware if practical.
- `docs/superpowers/` is untracked in this repo and was left untouched — out of scope for this task.
