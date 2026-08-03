# 0002 — Property names never cross the wire; plain objects inside a compilation unit are fine

**Status:** accepted · 2026-08-03
**Applies to:** web client, web-proxy
**Supersedes:** the `web-client/externs/api-response.js` workaround (deleted)

## Decision

Two rules, and the boundary between them is the **compilation unit**:

1. **Nothing crossing the wire carries property names.** `web-proxy` and the
   browser exchange **packed positional arrays** only — the DTOs in `api/dto/`.
   Names live in a `Fields` enum the compiler is free to rename.
2. **Plain object literals inside the compiled bundle are fine.** A view-model
   built in `controller.js` and handed straight to a Soy template — such as
   `withFormattedScore_`'s `{title, details, source, scoreDisplay}` — is
   legitimate and needs no DTO.

## Why the boundary sits exactly there

Closure ADVANCED compilation renames property accesses. Whether that is safe
depends entirely on whether **both the write and the read are compiled together**.

- **Inside the bundle:** `controller.js` writes `scoreDisplay` and the generated
  Soy code reads `scoreDisplay`. Both are in the same compilation, so both become
  the same renamed symbol. They cannot disagree. Safe.
- **Across the wire:** `web-proxy` is Node and is never compiled. It writes the
  literal string key `"score"`. The browser is compiled and reads a renamed
  property. The two sides are compiled separately, so nothing keeps them in
  agreement. **Unsafe.**

## The failure mode this prevents

When it breaks, it breaks **silently**: the bundle compiles cleanly, the network
request succeeds, the template renders, and every field reads `undefined`. There
is no error in any log, on either side. It was found live in a browser, not by
any test or build.

`externs/api-response.js` addressed this by declaring the wire property names so
the compiler left them alone. That worked, but it was a patch: it required every
wire field to be mirrored by hand in a second file, and forgetting one produced
exactly the silent failure above. Packed arrays remove the problem instead —
there is no name left on the wire for renaming to break.

## Practical test

Before adding a field, ask: **does this object get serialised?**

- **Yes** → it must be a DTO in `api/dto/` with an append-only slot, packed via
  `toJSON()` and read via `fromJSON()`. Add the slot at the end. Never reorder.
- **No** → a plain object literal is fine. Do not add a DTO for it.

## Consequence

`withFormattedScore_` building a fresh row object rather than mutating a
`Recommendation` DTO is **correct**, not a deviation to be tidied away later.
`scoreDisplay` is presentation, computed for the template and never serialised,
so it does not belong in the DTO layer and adding it there would widen the wire
contract for no reason.

## Revisit if

- Server-side rendering is introduced, which would compile templates against
  data produced outside the browser's compilation unit
- `web-proxy` is ever compiled with Closure, which would collapse the boundary
  this decision rests on
