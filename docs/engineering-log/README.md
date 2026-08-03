# Engineering log

Implementation and verification reports written while building this repo. They
are working artifacts, not customer deliverables — kept because several are the
evidence behind claims made in the deck and the architecture docs:

| Report | What it evidences |
|---|---|
| `task-real-endpoints-report.md` | The probing of the customer's live vendor services that produced the "your brief is wrong about your own services" finding (deck slide 6) — response shapes, error envelopes, duplicate items |
| `task-mobile-verification-report.md` | iOS simulator and Android emulator runs against the live edge, row by row |
| `task-security-fixes-report.md` | The fail-closed auth change and its three token states |
| `task-tls-repoint-report.md` | The gRPC-over-TLS repoint and the DigitalOcean ingress finding (deck slide 10) |
| `task-correctness-fixes-report.md` | Ranking, dedupe and provider-status branch-order fixes |
| `task-ui-parity-report.md`, `task-ui-sorting-picker-report.md` | Cross-platform UI parity checks |
| `task-mobile-plans-report.md`, `task-presentation-report.md` | Planning notes |

The deliverables live one level up: `docs/architecture-diagrams.md`,
`docs/deck/`, `docs/decisions/`, `docs/demo-script-1.2.0.md`,
`docs/deploy-1.2.0.md`, `docs/integrations/`, `docs/mobile/`.
