# 0003 — Generated protobuf sources are committed on iOS, generated at build time on Android

**Status:** accepted · 2026-08-03
**Applies to:** `apple-client/`, `android-client/`

## Decision

The two mobile clients treat generated protobuf code differently, and the
asymmetry is deliberate:

| | Generated code | Committed? |
|---|---|---|
| **Android** | `protobuf-gradle-plugin` regenerates from `api/proto/` on every build | No |
| **iOS** | `protoc` + the Objective-C plugin, run by hand | **Yes** — `apple-client/FunWithActivityCore/Generated/` |

The general rule is that generated code does not belong in version control,
and Android follows it. iOS deliberately does not.

## Why iOS is the exception

**This repository is public and is itself a deliverable.** Someone may clone
it to look at the code or build the app, and the cost of each option falls on
them, not on us.

- **Android's toolchain is self-installing.** The Gradle plugin fetches
  `protoc` and the Java plugin automatically. A clean clone builds with no
  manual setup, so committing generated sources would add noise for nothing.
- **iOS's is not.** Generating requires `protoc` *and* `protoc-gen-objc`
  present on the machine. If the generated sources were absent, a reviewer
  cloning the repo could not build the iOS app until they had installed a
  protobuf toolchain — a barrier with no upside for them.

Committing them makes the repository build from a clean clone on both
platforms. That property is worth more here than consistency between the two
build systems.

## The cost, stated plainly

**A change to `api/proto/recommendations.proto` is invisible to iOS until
those files are regenerated.** Android picks it up on the next build; iOS
does not, and the failure presents as a missing property rather than as a
stale artifact — which reads like a code error and sends you looking in the
wrong place.

This is not hypothetical. Adding `base_url` (field 7) to `ProviderStatus`
required regenerating the iOS sources as a separate, easily-forgotten step.

**Anyone changing the proto must regenerate the iOS sources in the same
commit.** Treat the generated files as part of the proto change, not as a
follow-up.

## Revisit if

- The repository stops being a public deliverable, at which point Android's
  approach is simply correct and iOS should follow it
- The iOS build gains a generation step of its own (an Xcode build phase or
  a `make` target run before building), which removes the toolchain barrier
  and makes committing them pointless
- Proto changes become frequent enough that the manual step is forgotten
  more than once — the frequency, not the principle, is what would make the
  current arrangement wrong
