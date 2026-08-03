# FunWithActivity — Architecture Diagrams

Three diagrams, each answering one question the deck asks and does not yet show a
picture of: what talks to what, what happens during one recommendation call, and
where the system is designed to grow. Kept deliberately small — a diagram nobody
can read from the back of the room is worse than no diagram.

---

## 1. System topology

The single most misunderstood thing about this system: **mobile never touches
`web-proxy`.** Browsers go through the REST façade; iOS and Android go straight
to the nginx edge over gRPC and never see `web-proxy` at all. The nginx edge
exists for one reason — DigitalOcean App Platform's ingress proxies HTTP/1.1 to
containers, and the Go gRPC server speaks h2c only, so native clients need a
tier that can terminate TLS and forward gRPC natively (`grpc_pass`). Browsers
never hit that limitation because they're not speaking gRPC in the first place.

```mermaid
flowchart LR
    Browser(["Browser"])
    iOS(["iOS app"])
    Android(["Android app"])

    WebProxy["web-proxy (Node)<br/>REST facade"]
    NginxEdge["nginx edge<br/>TLS termination, gRPC routing"]
    AppServer["app-server (Go)<br/>gRPC service"]
    Service1["service1 (Lambda)"]
    Service2["service2 (Lambda)"]
    EdgeNote["Exists because App Platform's ingress is<br/>HTTP/1.1-only and cannot carry gRPC"]

    Browser -- "HTTP/JSON" --> WebProxy
    WebProxy -- "gRPC" --> AppServer

    iOS -- "gRPC/TLS" --> NginxEdge
    Android -- "gRPC/TLS" --> NginxEdge
    NginxEdge -- "gRPC (h2c)" --> AppServer

    AppServer -- "HTTP/JSON" --> Service1
    AppServer -- "HTTP/JSON" --> Service2

    EdgeNote -.-> NginxEdge

    classDef note fill:#fff9db,stroke:#c9a227,stroke-dasharray: 3 3,color:#1a1a1a;
    class EdgeNote note;

    classDef mobile stroke:#0b6e4f,stroke-width:2px;
    class iOS,Android,NginxEdge mobile;
```

In production (AWS), an ALB with a gRPC target group replaces the nginx edge —
the workaround is specific to this one PaaS, not to the architecture.

---

## 2. Request flow for one recommendation call

The three provider outcomes — **OK**, **SKIPPED**, **DEGRADED** — are deliberately
distinct states, not points on one failure scale, because conflating skipped
with failed is the single most defect-prone thing in this codebase. A provider
is **skipped** when the data-minimisation gate never calls it at all (no birth
date ⇒ `service2` is skipped — GDPR data minimisation, not an error). A provider
is **degraded** when it *was* called and then timed out or errored. Either way,
the response still renders: partial results survive a provider failure, and the
per-request status list tells the client which is which.

```mermaid
flowchart TD
    M["Measurements arrive<br/>height, weight, optional birth date"]
    Gate{"Data-minimisation gate<br/>Provider.Requires() vs. fields present"}

    M --> Gate

    Gate -- "always eligible" --> S1Call["Call service1<br/>(2s timeout)"]
    Gate -- "birth date present" --> S2Call["Call service2<br/>(2s timeout)"]
    Gate -- "birth date absent" --> S2Skip["service2: SKIPPED<br/>(not called, not failed)"]

    S1Call -- "responds in time" --> S1Ok["service1: OK"]
    S1Call -- "timeout / error" --> S1Deg["service1: DEGRADED"]

    S2Call -- "responds in time" --> S2Ok["service2: OK"]
    S2Call -- "timeout / error" --> S2Deg["service2: DEGRADED"]

    S1Ok --> Merge["Merge -> dedupe -> rank<br/>(across whichever providers returned OK)"]
    S2Ok --> Merge

    Merge --> Resp["Response:<br/>recommendations[] + per-provider status[]"]
    S1Deg -.-> Resp
    S2Deg -.-> Resp
    S2Skip -.-> Resp

    classDef ok fill:#d4edda,stroke:#28a745,color:#1a1a1a;
    classDef skipped fill:#e2e3e5,stroke:#6c757d,color:#1a1a1a,stroke-dasharray: 4 3;
    classDef degraded fill:#f8d7da,stroke:#dc3545,color:#1a1a1a;

    class S1Ok,S2Ok ok;
    class S2Skip skipped;
    class S1Deg,S2Deg degraded;
```

Green = **OK** (results contributed to ranking). Grey/dashed = **SKIPPED**
(never called, no failure to report). Red = **DEGRADED** (called, failed or
timed out, no results but not fatal to the request).

---

## 3. The five extension seams

This is the direct answer to the customer's first stated requirement —
*"extensible architecture design."* Extensibility here is not one seam, it's
five, and the organising rule is: **gRPC is the boundary for things we control
on both ends; adapters and REST are the boundary for things we don't.** Each
seam below is a place a new provider, device, partner, client, or internal
service plugs in without changing the core.

```mermaid
flowchart TD
    Core(("app-server core<br/>fan-out, normalise, rank, dedupe"))

    Seam1["Seam 1: Recommendation provider<br/>Provider interface + registry"]
    Seam2["Seam 2: Device / sensor<br/>DeviceAdapter + capability registry"]
    Seam3["Seam 3: Partner / reseller<br/>Public integration API"]
    Seam4["Seam 4: Client app<br/>Public API surface"]
    Seam5["Seam 5: Internal service<br/>Proto contract"]

    New1["+ new provider<br/>e.g. service3"]:::new
    New2["+ new device<br/>e.g. Garmin OAuth adapter"]:::new
    New3["+ new partner<br/>e.g. gym chain"]:::new
    New4["+ new client<br/>e.g. tvOS"]:::new
    New5["+ new internal service<br/>e.g. billing"]:::new

    Seam1 -- "HTTP/JSON (vendor's choice)" --> Core
    Seam2 -- "HealthKit, Health Connect, BLE GATT, OAuth" --> Core
    Seam3 -- "REST + OpenAPI + webhooks" --> Core
    Seam4 -- "gRPC (native); REST facade (browsers)" --> Core
    Seam5 -- "gRPC (proto contract)" --> Core

    New1 -.-> Seam1
    New2 -.-> Seam2
    New3 -.-> Seam3
    New4 -.-> Seam4
    New5 -.-> Seam5

    classDef new fill:#fff3cd,stroke:#d4a017,stroke-dasharray: 4 3,color:#1a1a1a;
```

The brief names only seams 1 (providers) and 2 (devices) explicitly. Seam 3
(resellers/gyms) is directly implied by the "expanding aggressively" language.
Seams 4 and 5 are the ones a generic vendor deck tends to miss entirely.
