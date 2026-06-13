# AppLens — Project Constitution

AppLens is an open-source, graph-based autonomous QA tool for Flutter apps. This
file is the constitution: its rules bind **every** session and every change.
Refuse shortcuts that violate them. The binding design lives in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md); the session plan and acceptance
gates live in [`docs/BUILD-PLAN.md`](docs/BUILD-PLAN.md); the scaffold contract
lives in [`docs/SCAFFOLD.md`](docs/SCAFFOLD.md). When code and a spec disagree,
fix one of them in the same session — never let them drift.

## How to work a session

One session = one bounded goal = one PR. Read `docs/ARCHITECTURE.md`,
`docs/BUILD-PLAN.md`, and this file first. Work **only** on the current session's
tasks. Confirm the previous session's acceptance gate still passes before
starting, and leave the current gate green. A session that ends red is not done.

## Architecture invariants

- Nothing above `DriverInterface` may import any driver implementation. The
  action engine is first-party, built only on Flutter SDK APIs (flutter_test
  primitives, integration_test, GestureBinding, TestTextInput). **Patrol does not
  appear in v1 in any form.**
- **AI is advisory, never gating.** No AI call may ever decide pass/fail. The
  deterministic core must produce identical results for identical inputs — same
  graph + same seed = same verdict.
- Every mutation of graph YAML or baselines flows through a PR. No code path
  writes to the graph directory outside the proposal/PR mechanism.
- Execution history never lives in node YAML; it lives in the run store.
- Dependency policy is a 5-rung ladder: depend → depend + own orchestration →
  upstream PR → tracking fork → clean rebuild. Hard forks (copy and diverge) are
  banned. Before adding any pub dependency, justify it in the PR description
  against this ladder.

## Engineering rules

- Clean, extensible code; no over-engineering, no workarounds, no speculative
  abstractions, no unnecessary comments. Public APIs get doc comments; nothing
  else does unless non-obvious.
- Algorithmic components (pixelmatch port, layout hash, path compiler, fingerprint
  matcher) are built **test-first**: port/write the test fixtures before the
  implementation.
- Every package keeps `dart analyze --fatal-infos` clean with strict lints and its
  tests green at the end of every session.
- **Walking-skeleton discipline:** build the thinnest end-to-end slice first,
  generalize only after it runs. Resist completing any layer "while we're here."
- **The stranger-app rule:** `examples/stranger_app` must work using only the
  public interface and the README. The day it needs special access, stop and fix
  the product, not the example.
- Conventional commits; one logical change per commit; never commit generated
  goldens or run artifacts except the stranger app's intentional fixtures.

## Human checkpoints (what cannot be done unattended)

- Anything requiring a live emulator/device run is verified by a human. Prepare
  the exact commands and expected output; structure every emulator-dependent task
  so its logic is unit-testable headless first (fake driver, recorded tree
  snapshots) and the device run is confirmation, not discovery.
- pub.dev publishing, GitHub repo settings, branch protection, and Action secrets
  are human tasks.

## Standing verification (end of every session)

```bash
dart pub get                                       # resolves the whole workspace
dart pub global activate melos                     # one-time: puts `melos` on PATH
melos run ci                                       # format → analyze → boundaries → tests, headless
# (once the CLI exists) applens validate examples/stranger_app/qa_graph
git diff --stat docs/                              # behavior changed ⇒ spec changed
```

During Phases 1–2 (before Session 9), triage failures by hand and save each as an
evidence→verdict pair under `docs/triage-evals/` — that becomes the eval set for
the automated providers later.

## Workspace mechanics (current tooling, confirmed Session 0)

- Pub workspace (Dart `^3.9.0`); `dart pub get` at the root resolves everything.
  Melos `^7.0.0` provides scripting only — its config lives in the root
  `pubspec.yaml` under `melos:`. There is no `melos.yaml`. Melos must be
  globally activated (`dart pub global activate melos`): its `exec:` scripts
  shell out to a bare `melos`, so the binary must be on `PATH`.
- Analyze and test are split by package kind: Flutter packages use
  `flutter analyze`/`flutter test` (dart:ui is engine-provided), pure-Dart
  packages use the Dart toolchain, and the workspace-root tooling (the boundary
  checker) is handled by the `*-tooling` scripts since melos does not iterate the
  root package itself.
- Lints: `package:lints` for pure-Dart packages (root `analysis_options.yaml`),
  `package:flutter_lints` for Flutter packages (`analysis_options_flutter.yaml`).
  `require_trailing_commas` is intentionally absent (deprecated; conflicts with
  the Dart 3.7+ formatter).
- The import-boundary invariant is enforced mechanically by
  `tool/check_boundaries.dart` (run in CI), not by review.
