# Provider: <name>

## Endpoint
- URL (env var):
- Method:
- Auth:

## Request
| Our field | Their field | Their unit | Conversion |
|---|---|---|---|

## Success response
- Shape (array | object):
- Score field, and its range:
- Normalisation to 0..1:

## Error response
- Shape:
- Code field / message field:
- Discriminator (how we tell success from error):

## Required inputs
`Requires()` returns: <FieldSet>

## Checklist
- [ ] Adapter implements `providers.Provider` in `app-server/internal/providers/<name>.go`
- [ ] Registered in `registry.go`
- [ ] Table test with httptest covering: success, error envelope, malformed body, Requires()
- [ ] Trust weight added to `RANKER_WEIGHTS`
