# web-server — the edge tier

nginx. Deliberately separate from `web-proxy`.

`web-proxy` is an **application** tier: a BFF for browsers serving the REST API and
the compiled Closure bundle. Edge concerns — TLS termination, rate limiting,
routing, and later WAF and DDoS controls — belong here, in front of *both*
backends.

```
             ┌─────────────── nginx (TLS, rate limit, route) ───────────────┐
 native ──── │ /funwithactivity.recommendations.v1.*  →  app-server :50051  │  gRPC / HTTP2
 browsers ── │ /                                      →  web-proxy  :3000   │  HTTP/1.1
             └──────────────────────────────────────────────────────────────┘
```

## Why this tier exists

DigitalOcean App Platform's ingress proxies **HTTP/1.1** to containers, so a Go
gRPC server (which speaks h2c only) is unreachable through it. Verified
empirically — `grpcurl` returns `upstream connect error ... reset reason:
protocol error`, and a plain `curl` to the same port negotiates HTTP/1.1 and
times out.

That is a limitation of one PaaS, not of the architecture. AWS ALB with a gRPC
target group, GCP Cloud Run, and Azure Container Apps all speak HTTP/2 to
targets natively. The production recommendation (AWS) is unaffected.

## Files

- `nginx-grpc.conf` — the edge config. `__HOST__` is substituted at provision time.
- `provision.sh` — provisions a Droplet: cross-compiles app-server, installs it
  under systemd bound to loopback, obtains a Let's Encrypt certificate, and
  installs this nginx config.

## TLS without buying a domain

`provision.sh` uses `<ip>.sslip.io`, which resolves to the IP and is issuable by
Let's Encrypt. A **publicly trusted** certificate matters: iOS App Transport
Security and Android's default network security config both reject self-signed
certificates without per-app exceptions.

## Not enabled here

Server reflection is **not** routed through this edge. app-server registers
`grpc.reflection.v1` and `grpc.reflection.v1alpha` and its `authInterceptor`
bypasses auth for both (so loopback tooling — e.g. `grpcurl` against
`localhost:50051` directly, or a health probe — keeps working), but
`nginx-grpc.conf` has no `location` block for either reflection service, so
neither is reachable from outside. Routing them here would publish the full
service schema to anonymous callers. If you need `grpcurl` against the public
edge during a demo, tunnel to the loopback port instead of adding a route.
