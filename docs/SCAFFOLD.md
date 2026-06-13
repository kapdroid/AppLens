# AppLens — Scaffold Spec (Session 0 companion)

Concrete, near-deterministic setup for Session 0. Companion to `ARCHITECTURE.md` (what to build)
and `BUILD-PLAN.md` (session order). This file removes improvisation from the scaffold: exact
workspace config, lint rules, package skeletons, the four core contracts as real Dart, and the
mechanical import-boundary check. Deliberately excludes process/agent orchestration — that is
added only if real friction during Sessions 0-1 demands it, per walking-skeleton discipline.

Two version-sensitive items to confirm live at Session 0 (do not guess — check current docs):
the melos version + whether pub workspaces (Dart 3.6+ `workspace:` field) replace melos bootstrap,
and the latest `package:lints` / `flutter_lints` versions. Everything else here is stable.

---

## 1. Workspace topology

Pub workspaces (Dart 3.6+) are now the native mechanism; melos rides on top for scripting.
Root `pubspec.yaml` declares the workspace; each package opts in with `resolution: workspace`.

Root `pubspec.yaml`:
```yaml
name: applens_workspace
publish_to: none
environment:
  sdk: ^3.6.0
workspace:
  - packages/applens_core
  - packages/applens_runner
  - packages/applens_cli
  - packages/applens_report
  - packages/applens_compare
  - packages/applens_sdk
  - packages/applens_crawler
  - packages/applens_llm
  - examples/stranger_app
dev_dependencies:
  melos: ^6.0.0          # confirm latest at Session 0
```

`melos.yaml` (scripting only — bootstrap is now `dart pub get` at root):
```yaml
name: applens
packages:
  - packages/**
  - examples/**
scripts:
  analyze:
    exec: dart analyze --fatal-infos
    description: Static analysis, infos treated as failures
  test:
    exec: dart test
    packageFilters:
      dirExists: test
  format-check:
    exec: dart format --output=none --set-exit-if-changed .
  boundaries:
    run: dart run tool/check_boundaries.dart
    description: Enforce architectural import boundaries
  ci:
    run: melos run format-check && melos run analyze && melos run boundaries && melos run test
```

---

## 2. Shared lint ruleset

Root `analysis_options.yaml`, inherited by every package via `include`:
```yaml
include: package:lints/recommended.yaml   # use flutter_lints in Flutter packages

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    # quality violations fail the build, not just warn
    invalid_annotation_target: error
    unused_import: error
    unused_local_variable: error
    dead_code: error
    todo: info        # TODOs allowed but surfaced
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"

linter:
  rules:
    - prefer_relative_imports          # within a package
    - always_declare_return_types
    - avoid_dynamic_calls
    - cancel_subscriptions
    - close_sinks
    - only_throw_errors
    - unawaited_futures
    - prefer_final_locals
    - avoid_redundant_argument_values
    - require_trailing_commas
```

Flutter packages (`applens_runner`, `applens_sdk`, `applens_compare`) use a sibling
`analysis_options.yaml` that does `include: package:flutter_lints/flutter.yaml` then layers the
same analyzer `strict-*` and `errors` block. Keep the two in sync; the strictness block is the
contract, the base import differs only because Flutter packages need the widget lints.

Rule of the constitution made mechanical: `dart analyze --fatal-infos` means a session that
leaves any info-level issue is red. No "clean enough."

---

## 3. Package skeletons

Each package: `pubspec.yaml`, `analysis_options.yaml` (one line: `include: ../../analysis_options.yaml`),
`lib/<name>.dart` (public barrel), `lib/src/` (implementation), `test/`. Dependency direction is
strictly downward — enforced in §5.

Layering (who may depend on whom):
```
applens_core      → (nothing internal)        pure model, compiler, validate
applens_llm       → applens_core              provider port + adapters
applens_runner    → applens_core, applens_compare  driver iface, oracles, run loop  [Flutter]
applens_compare   → (nothing internal)        standalone golden comparator     [Flutter]
applens_crawler   → applens_core, applens_runner
applens_report    → applens_core              static HTML generation
applens_cli       → all of the above          composition root
applens_sdk       → (nothing internal)        in-app: TestClock, introspection [Flutter]
```

`applens_core/pubspec.yaml`:
```yaml
name: applens_core
publish_to: none          # flip to real publish at first release
environment: { sdk: ^3.6.0 }
resolution: workspace
dependencies:
  yaml: ^3.1.0
  collection: ^1.18.0
dev_dependencies:
  test: ^1.25.0
```

`applens_runner/pubspec.yaml` (Flutter — the only heavy one):
```yaml
name: applens_runner
publish_to: none
environment: { sdk: ^3.6.0, flutter: ">=3.27.0" }
resolution: workspace
dependencies:
  flutter: { sdk: flutter }
  flutter_test: { sdk: flutter }
  integration_test: { sdk: flutter }
  applens_core: any        # workspace-resolved
  image: ^4.2.0            # PNG encode/decode only (§ comparator)
dev_dependencies:
  flutter_lints: ^5.0.0    # confirm latest at Session 0
```

The remaining six follow the same shape: `applens_llm` (+ `http`), `applens_compare` (Flutter +
`image`, zero internal deps), `applens_cli` (+ `args`, depends on all), `applens_report`
(+ a templating choice — plain string templates are fine, no dep needed), `applens_crawler`,
`applens_sdk` (Flutter, zero internal deps). Stub packages (`applens_sdk`, `applens_crawler` at
Session 0) ship a barrel file with a single documented placeholder and a passing smoke test, so
the workspace resolves and CI is green from commit one.

---

## 4. The four core contracts (write before Session 1)

Minimal interfaces — one job each, no speculative methods. Richer shapes are added only when a
session needs them. These four files are the fixed targets every later session builds against.

`applens_runner/lib/src/driver/driver.dart`:
```dart
/// The single seam between AppLens and any UI-driving backend.
/// NOTHING above this interface may import a concrete driver (enforced: tool/check_boundaries.dart).
abstract interface class AppLensDriver {
  Future<void> tap(WidgetSelector selector);
  Future<void> longPress(WidgetSelector selector);
  Future<void> enterText(WidgetSelector selector, String text);
  Future<void> scrollTo(WidgetSelector selector);
  Future<void> swipe(Offset from, Offset to);
  Future<void> back();
  Future<void> openDeepLink(Uri uri);
  Future<WidgetTreeSnapshot> tree();
  Future<Capture> capture(CaptureScope scope);
  Future<void> settle(SettlePolicy policy);

  /// Native OS surfaces (permission dialogs, notifications).
  /// v1: throws UnimplementedError — permissions are pre-granted, not automated (spec §7).
  Future<void> native(NativeAction action);
}
```

`applens_runner/lib/src/oracle/oracle.dart`:
```dart
/// One assertion tier. Tiers run cheap-to-expensive; a structural failure short-circuits.
abstract interface class OracleTier {
  /// Lower runs first. T1 tree=10, T2 layout=20, T3 pixel=30, T4 advisory=40.
  int get order;

  /// Evaluate this tier against the current state. Pure given its inputs —
  /// no tier may consult an LLM or any nondeterministic source.
  Future<OracleResult> evaluate(NodeSpec node, EvaluationContext context);
}
```

`applens_llm/lib/src/provider.dart`:
```dart
/// The seam where any LLM — or a human at a desktop chat — is swapped.
/// Sidecar logic speaks only LlmRequest/LlmResult; it never names a vendor.
abstract interface class LlmProvider {
  Future<LlmResult> complete(LlmRequest request);
  LlmCapabilities get capabilities;   // vision? jsonMode? maxContextTokens
}
```

`applens_core/lib/src/vcs/vcs_adapter.dart`:
```dart
/// The seam over GitHub / GitLab / ADO. v1 ships a GitHub implementation.
abstract interface class VcsAdapter {
  Future<PullRequest> openPr(PrDraft draft);

  /// Merge iff the diff satisfies the guard (e.g. baseline-only changes).
  /// The guard is evaluated by AppLens, not delegated to the host — determinism.
  Future<MergeResult> mergeIfGuardPasses(PullRequest pr, MergeGuard guard);
}
```

Each contract ships with its value types (`WidgetSelector`, `OracleResult`, `LlmRequest`, …) as
plain immutable classes in the same `src/` folder, and a barrel export. No implementations yet —
Session 3 fills `AppLensDriver`, Session 7 the tiers, Session 8.5 the providers, Session 8 the
GitHub adapter. Writing the interfaces first is the point: every session has an unmovable target.

---

## 5. Import-boundary enforcement (mechanical, not review-hoped)

The constitution's hard rule — "nothing above DriverInterface imports a driver; layering is
downward only" — is checked by a script in CI, so violation fails the build rather than slipping
past review.

`tool/check_boundaries.dart` (pure Dart, no deps; run in the `ci` script):
```dart
// Parses every lib/**/*.dart import and asserts the layering in §3.
// Rules encoded:
//  1. No file outside src/driver/ may import 'driver/driver_impl' or any concrete *Driver.
//  2. applens_core imports no other applens_* package.
//  3. applens_compare imports no other applens_* package.
//  4. applens_sdk imports no other applens_* package.
//  5. Dependency edges must match the allowed graph in §3 (no upward imports).
// Exit non-zero on any violation, printing file:line and the rule broken.
```
Implementation is a directory walk + regex on `import '...'` lines + a hardcoded adjacency map of
the allowed layering. ~120 lines. It is itself unit-tested with fixture files that should pass and
fail. This script is the teeth behind the most important architectural invariant; build it in
Session 0 so the boundary cannot rot from day one.

---

## 6. CI wiring (Session 0 GitHub Actions)

`.github/workflows/ci.yaml` runs on every push/PR:
```yaml
steps:
  - uses: actions/checkout@v4
  - uses: subosito/flutter-action@v2     # provides flutter + dart; confirm latest
    with: { channel: stable }
  - run: dart pub get                    # resolves the whole workspace
  - run: dart run melos run ci           # format-check → analyze → boundaries → test
```
No emulator in Session 0 CI — that arrives with the GitHub Action in Session 5. Keep Session 0 CI
headless and fast so every push is gated cheaply.

---

## 7. Session 0 acceptance gate (replaces the thinner one in BUILD-PLAN)

Fresh clone → `dart pub get` → `dart run melos run ci` is green, where green means: format clean,
`analyze --fatal-infos` clean across all eight packages, the boundary script passes (with its own
fixture tests green), every package's smoke test passes, and the stranger app builds. The four
contract files exist, export through barrels, and have no implementations. CLAUDE.md, ARCHITECTURE.md,
BUILD-PLAN.md, and this SCAFFOLD.md are committed. Only then does Session 1 begin.

---

## What this spec deliberately omits

No agent/skill orchestration matrix, no per-session "which model drives this" assignment, no
elaborate docs-as-source-of-truth ceremony beyond `git commit`. Those are process inventions that
should be earned by observed friction, not designed upfront — the same discipline that keeps the
product itself from over-abstracting. If Sessions 0-1 reveal a repeated stumble, encode a fix then.

---

## Session 0 — confirmed live (deviations from the draft above)

The version-sensitive items §1 said to confirm rather than guess, plus the friction the scaffold
actually hit, resolved in-session per the constitution ("never let code and spec drift"):

- **Toolchain:** Dart 3.9.2 / Flutter 3.35.7 (stable). Confirmed latest: melos **7.8.2**, lints
  **6.1.0**, flutter_lints **6.0.0**, image 4.9.1, args 2.7.0, yaml 3.1.3, collection 1.19.1,
  test 1.26.x. Root SDK constraint is `^3.9.0` (melos 7 requires it); library packages keep `^3.6.0`.
- **Pub workspaces replace `melos bootstrap`:** `dart pub get` at the root resolves everything.
  Melos 7 reads its config from the root `pubspec.yaml` under a `melos:` key — there is no
  `melos.yaml`. **Melos must be globally activated** (`dart pub global activate melos`): a named
  `exec:` script is sugar for a bare `melos exec …`, so the binary must be on `PATH`. CI activates
  it and adds `~/.pub-cache/bin` to the path; the gate command is `melos run ci`.
- **Analyze/test split by package kind:** `dart analyze` cannot resolve `dart:ui`, so Flutter
  packages use `flutter analyze`/`flutter test` and pure-Dart packages use the Dart toolchain. The
  workspace-root tooling (the boundary checker under `tool/` + its tests under `test/`) is not a
  workspace member, so dedicated `analyze-tooling`/`test-tooling` scripts cover it.
- **`require_trailing_commas` dropped** from the §2 lint list: it is deprecated and conflicts with
  the Dart 3.7+ formatter, which manages commas itself. `dart format` (via `format-check`) enforces
  comma style instead.
- **stranger_app** is an original demo authored for this repo (Apache-2.0) rather than a vendored
  third-party app — cleaner license story, same zero-special-access contract. Its "build" proof in
  the headless gate is `flutter test` (compile + widget-tree + the scroll-into-long-list flow); the
  full emulator build/run is the Session 5 walking-skeleton gate.
