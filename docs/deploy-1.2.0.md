# 1.2.0 stack — deployment

The 1.2.0 work runs on its own App Platform app, fully isolated from the
1.1.x stack. Nothing is shared between them except the two vendor endpoints.

| | value |
|---|---|
| App name | `funwithactivity2` |
| App ID | `14747765-f904-4e43-921c-2ea305363de5` |
| URL | https://funwithactivity2-ehr57.ondigitalocean.app |
| Repo | this one, `main`, `deploy_on_push: true` |

## Configuration lives in the DO dashboard, not in this repo

`deploy/app-platform.yaml` ships **placeholders**. Three values are set in the
App Platform console and never committed:

| Key | Component | Type |
|---|---|---|
| `PROVIDER1_URL` | app-server | plain |
| `PROVIDER2_URL` | app-server | plain |
| `INTERNAL_GRPC_TOKEN` | app-server **and** web-proxy | encrypted |

`INTERNAL_GRPC_TOKEN` must be **byte-identical on both components**. They
authenticate to each other with it, and a mismatch surfaces as
`16 UNAUTHENTICATED: invalid token` in the web-proxy logs while the browser
sees a gateway error — which reads as a network fault rather than a config
one. This is not hypothetical; it happened on first setup. Generate once and
paste the same string into both:

```bash
openssl rand -hex 24 | tee /dev/tty | pbcopy
```

Saving any environment variable triggers an automatic redeploy.

## Verifying a deploy

Watch it reach `ACTIVE` rather than trusting the push — a push and a spec
update racing each other has previously produced a green report against a
stale build.

```bash
APP=14747765-f904-4e43-921c-2ea305363de5
DEP=$(doctl apps list-deployments $APP --format ID --no-header | head -1)
doctl apps get-deployment $APP $DEP --format Phase --no-header
```

Then confirm real data is being served. The vendors are cold-start Lambdas:
the first call after idle can time out with both providers unavailable, and
`service2` fails on roughly a third of calls by design. Make three calls
before concluding anything.

```bash
curl -s -X POST https://funwithactivity2-ehr57.ondigitalocean.app/api/recommendations \
  -H 'content-type: application/json' \
  -d '{"heightCm":184,"weightKg":84,"birthDateUnix":668995200,"faults":{}}'
```

Expect a packed positional array `[[...],[...]]`, not an object. A tip both
vendors returned shows `"service1, service2"` as its source and carries the
details text only `service2` supplies.
