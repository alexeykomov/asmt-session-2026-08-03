# FunWithActivity

Recommendations-aggregation skeleton for the EPAM pre-sale demo. Fans out to multiple provider adapters and exposes a merged, ranked recommendation set. Target architecture: Go gRPC app-server + Node web-proxy + Closure web-client.

## Architecture (one-liner)

```
Browser ──HTTP/JSON──► web-proxy ──gRPC──► app-server ──► provider adapters
```

- `app-server/` (Go 1.23) — provider fan-out + ranking, gRPC server on `:50051`, HTTP `/health` sidecar on `:50052`.
- `web-proxy/` (Node + Express) — public REST façade, calls app-server over gRPC.
- `web-client/` — Closure Library SPA (planned).
- `api/proto/` — single proto contract (`recommendations.proto`) for the internal gRPC API; `generate_all.sh` drives Go + JS codegen.

## Status

This is Task 1 of the build plan: repository scaffold and the proto contract only. No server implementation, no web-proxy, no web-client yet — those land in later tasks.

## Prerequisites

- Go 1.23+
- Node 18+
- `protoc` 3+ and the Go plugins (`protoc-gen-go` v1.31.0, `protoc-gen-go-grpc` v1.3.0) for proto codegen

## Codegen

```
make codegen
ls api/gen/go/funwithactivity/api/   # recommendations.pb.go, recommendations_grpc.pb.go
```

`api/gen/` is generated output and is git-ignored — regenerate it locally with `make codegen`.

## Local development

`web-client` is a Closure Library SPA: `ui-soy/` templates are compiled to
JS and then bundled with Closure Compiler into a single ADVANCED-mode
`web-client/public/main.min.js`, served as a static file.

```
cd web-client
npm install
npm run build   # scripts/compile-soy.js, then scripts/compile.js
npm run lint
```

**Java is needed only to build the client, never to run it.** Both build
steps shell out to a jar (the Soy-to-JS compiler, and Closure Compiler's
own `compiler.jar`), so a JRE (Java 17+) must be on `PATH` wherever
`npm run build` runs. Once `web-client/public/` exists, `web-proxy` serves
it as plain static files — it has no Soy/Java dependency at build or run
time, and `web-proxy/Dockerfile`'s runtime stage has no JRE installed; only
its `client-builder` stage does.

```
cd web-proxy
npm install
npm test
PORT=3000 APP_SERVER_URL=localhost:50051 npm start
```
