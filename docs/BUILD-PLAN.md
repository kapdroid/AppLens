# AppLens — Claude Code Build Plan (end to end)

Companion to `applens-architecture-spec.md`. Put both files in the repo before the first session:
the spec at `docs/ARCHITECTURE.md`, this file at `docs/BUILD-PLAN.md`. Claude Code reads them; they are
the source of truth. When code and spec disagree, fix one of them in the same session — never let them drift.

---

## 0. The kickoff prompt (paste this to start Session 0)

```
You are building AppLens, an open-source graph-based autonomous QA tool for Flutter apps.
Read docs/ARCHITECTURE.md fully before writing anything — it is the binding design.
Read docs/BUILD-PLAN.md — it defines the session you are in, its tasks, and its acceptance
gate. Work ONLY on the current session's tasks. Create CLAUDE.md at the repo root with the
project constitution from BUILD-PLAN.md section 1 so every future session inherits the rules.
We are starting Session 0: repository scaffold — follow docs/SCAFFOLD.md exactly (it has the concrete melos.yaml, lints, pubspecs, the four core contracts, and the boundary script). Begin.
```

Every later session starts with: `Read CLAUDE.md, docs/ARCHITECTURE.md and docs/BUILD-PLAN.md.
We are in Session N. Confirm the previous session's acceptance gate still passes, then begin.`

---

## 1. Project constitution (becomes CLAUDE.md at repo root)

These rules bind every session. Claude Code must refuse shortcuts that violate them.

**Architecture invariants**
- Nothing above DriverInterface may import any driver implementation. The action engine is
  first-party, built only on Flutter SDK APIs (flutter_test primitives, integration_test,
  GestureBinding, TestTextInput). Patrol does not appear in v1 in any form.
- AI is advisory, never gating: no AI call may ever decide pass/fail. The deterministic core
  must produce identical results for identical inputs — same graph + same seed = same verdict.
- Every mutation of graph YAML or baselines flows through a PR. No code path writes to the
  graph directory outside the proposal/PR mechanism.
- Execution history never lives in node YAML; it lives in the run store.
- Dependency policy is a 5-rung ladder: depend → depend + own orchestration → upstream PR →
  tracking fork → clean rebuild. Hard forks (copy and diverge) are banned. Before adding any
  pub dependency, justify it in the PR description against this ladder.

**Engineering rules**
- Clean, extensible code; no over-engineering, no workarounds, no speculative abstractions,
  no unnecessary comments. Public APIs get doc comments; nothing else does unless non-obvious.
- Algorithmic components (pixelmatch port, layout hash, path compiler, fingerprint matcher)
  are built TEST-FIRST: port/write the test fixtures before the implementation.
- Every package keeps `dart analyze` clean with strict lints and `dart test` green at the end
  of every session. A session that ends red is not done.
- Walking-skeleton discipline: build the thinnest end-to-end slice first, generalize only
  after it runs. Resist completing any layer "while we're here."
- The stranger-app rule: examples/stranger_app must work using only the public interface and
  the README. The day it needs special access, stop and fix the product, not the example.
- Conventional commits; one logical change per commit; never commit generated goldens or
  run artifacts except the stranger app's intentional fixtures.

**What Claude Code cannot do alone (human checkpoints)**
- Anything requiring a live emulator/device run is verified by the human. Claude Code prepares
  the exact commands and expected output; the human runs them and pastes results back.
  Structure every emulator-dependent task so its logic is unit-testable headless first
  (fake driver, recorded tree snapshots) and the device run is confirmation, not discovery.
- pub.dev publishing, GitHub repo settings, branch protection, and Action secrets are human tasks.

---

## 2. Working method

One session = one bounded goal = one PR. Sessions below are sized for a focused Claude Code
run plus a human verification pass. Each has Tasks, then an **Acceptance gate** — the gate is
binary and must pass before the next session starts. If a session uncovers a spec gap, the
session's last task becomes updating docs/ARCHITECTURE.md.

Test pyramid per package: pure-Dart unit tests for all logic (runs in CI on every push);
a FakeDriver (scripted tree snapshots + action log) so the entire runner/orchestrator is
testable without any device; emulator integration tests only in the stranger-app workflow.

---

## 3. Sessions

### Session 0 — Scaffold
Tasks:
1. Dart workspace monorepo: packages/ applens_core, applens_runner, applens_cli, applens_report,
   applens_compare, applens_sdk, applens_crawler, applens_llm (sdk/crawler as stubs); melos or pub workspaces; shared
   strict analysis_options; LICENSE (Apache-2.0); CLAUDE.md from section 1; README placeholder.
2. GitHub Actions CI: analyze + test on every push for all packages (no emulator yet).
3. examples/stranger_app: vendor a small open-source Flutter demo app (e.g. a standard
   shopping-list/counter-style sample with 4-6 screens and one long scrollable list) with
   attribution; it must build.
Acceptance gate: fresh clone → `melos bootstrap && melos run analyze && melos run test` green
in CI; stranger app builds.

### Session 1 — Graph model (applens_core)
Tasks:
1. Typed model: Node (identity: route, anchors, flags, overlay; payload: assertions, baselines,
   edges, guards, tags, owner), Edge, actions enum per spec §4. YAML parse/serialize with
   precise error messages (file, line, what's wrong).
2. `validate`: schema validity, dangling edge targets, reachability from entry nodes, orphan
   baseline refs, and fingerprint-ambiguity detection (any two nodes whose identity sets cannot
   be distinguished = hard error). Unit tests include deliberately ambiguous graphs.
3. Graph content hash (stable across key ordering) for plan staleness checks.
4. Module-mirrored loading (spec §5): walk qa_graph/modules/*/nodes/*.yaml, resolve hierarchical
   node IDs (order.confirm) and `includes:` composition from shared/ fragments before validation.
   Composition is resolve-then-validate so an ambiguity in an included fragment is still caught.
Acceptance gate: a hand-written 5-node graph for the stranger app (write it now under
examples/stranger_app/qa_graph/modules/, using one shared/ include to prove composition) parses,
validates, round-trips; ambiguity fixtures fail with the right errors.

### Session 2 — Path compiler (applens_core)
Tasks:
1. Plan model + human-readable plan YAML embedding the graph hash.
2. Strategies: smoke (node coverage of tagged nodes via shortest paths) and regression
   (directed edge coverage via Chinese-postman heuristic — determinism required, optimality not).
   impact and soak are stubs with TODOs referencing spec §5.
3. Per-node top-k alternate inbound paths, precomputed into the plan (for hard-fail reroute).
4. Property tests: every plan covers what its strategy promises; same graph + strategy + seed
   → byte-identical plan.
Acceptance gate: plans compile for the stranger graph; coverage properties hold under tests.

### Session 3 — Action engine (applens_runner, headless-testable)
Tasks:
1. DriverInterface exactly as spec §6 (native() throws UnimplementedError with a message
   pointing to the Phase 3 decision).
2. AppLensDriver on SDK APIs: key/semantics selector resolution, hit-test verification before
   tap (rich failure message naming the obscuring widget), tap/long-press/swipe via synthetic
   pointer events, scrollTo as physics-respecting repeated drags with sliver/nested-scrollable
   handling, enterText via TestTextInput (IME emulation — never key taps), back via the root
   Navigator.maybePop (the public equivalent of the @protected handlePopRoute;
   on-device back fidelity is revisited at Session 5), deep links via platform channel.
3. FakeDriver + recorded-tree test harness; unit-test every action's logic headless.
4. Settle policy incl. consecutive-identical-frames stabilization (frame compare is unit-tested
   with synthetic frame bytes).
Acceptance gate: all action logic green headless; a minimal widget-test-bed exercises tap,
scroll-into-long-list, and enterText against real Flutter widgets in plain `flutter test`.

### Session 4 — Runner loop (applens_runner)
Tasks:
1. Orchestrator: execute plan step → act → settle → fingerprint (route observer + anchor probe
   + flags via introspection-or-inference) → match node → run tier-1 assertions → record.
2. Outcome semantics: passed, failed_soft (continue), failed_hard (consume precomputed
   alternates, reroute), blocked, plus the unexpected-transition event.
3. Failure artifacts: full-screen capture, serialized tree, log tail per failed visit.
4. Run store v0: SQLite file; runs, node_visits, assertion_results, artifacts.
Acceptance gate: full plan executes against FakeDriver scripts simulating: clean pass, a soft
fail, a hard fail with successful reroute, and an unexpected transition — all outcomes recorded
correctly. Entire gate runs headless in CI.

### Session 5 — CLI + report + the skeleton lands (applens_cli, applens_report)
Tasks:
1. `applens init` (entrypoint generation with NavigatorObserver, qa_graph scaffold, applens.yaml
   with permissions list), `applens validate`, `applens plan`, `applens run`, `applens report`.
   Pre-grant: CLI applies adb/simctl permission grants at session start.
2. Static HTML report: per-node outcomes, coverage %, artifact links; CI exit codes 0/1/2.
   Failures are self-locating (spec §5): each carries the node's file path and assertion locus
   (modules/order/nodes/confirm.yaml:assertions[2]) plus a rendered subgraph with the failing
   node highlighted among its neighbors.
3. `applens graph` command family (the human interface to a large graph, spec §5):
   `graph show <module>` renders a module subgraph in the browser from YAML (reuse the report
   render engine); `graph find --tag/--owner` queries; `graph path <a> <b>`; `graph stats`
   (counts, orphans, per-module coverage). These make file count irrelevant to comprehension.
4. GitHub Action (actions/applens-run): emulator boot + run + report upload + PR comment.
5. README v1: the fifteen-minute walkthrough, written against the stranger app.
Acceptance gate — THE WALKING SKELETON: human runs the README on the stranger app; nightly
workflow green two consecutive nights in GitHub Actions; one of the 5 nodes scrolls into a long
list. Until this gate passes, no Phase 2 work starts.

### Session 6 — Pixel comparator (applens_runner/visual + applens_compare)
Tasks:
1. Port mapbox/pixelmatch test fixtures FIRST; then the algorithm (YIQ delta, AA detection)
   until fixtures pass byte-identically. Attribution per ISC.
2. comparator.dart: widget-key masks applied to both images, dual thresholds, VisualVerdict
   with red diff PNG. Watch the RGBA byte-format trap: on-device captures from
   ui.Image.toByteData() are premultiplied rawRgba (no rawStraightRgba format exists), so
   Session 7 must reach this comparator via PNG encode; the algorithm expects straight RGBA.
3. applens_compare: GoldenFileComparator implementation; its own README; standalone package
   usable with zero AppLens knowledge.
Acceptance gate: upstream fixtures pass; applens_compare is a drop-in GoldenFileComparator that
tolerates a sub-threshold AA difference the default exact comparator rejects — proven at the
fixture level (a byte-different mapbox pair the stock GoldenFileComparator.compareLists rejects
while our drop-in passes), with the negative control executed. Deliberately NOT proven via a live
widget golden in the stranger app: a macOS-authored widget golden re-run on Linux CI diverges by
font hinting / subpixel AA far beyond one pixel (and Flutter enforces host-only goldens), which
would make the gate flaky for reasons unrelated to the comparator. The 2-line stranger-app
adoption is documented in applens_compare/README.md.

### Session 7 — Capture, tier 2/3, baseline recording
Tasks:
1. capture.dart: stabilized capture, derived scope (tree-diff → full/overlay-crop/region; note
   overlays mount under Overlay, not the page — handle it), mask resolution to rects.
2. Tier 2 layout hash (normalized tree shape, data stripped) — fixture-tested.
3. `applens baseline record`: proposals with provenance; approval writes node YAML; baselines
   keyed (node, device, locale, theme), content-addressed, LFS-ready.
4. Wire tiers into the orchestrator: cheap-to-expensive, short-circuit default.
Acceptance gate: stranger app gets goldens on 2 tagged nodes incl. one dialog crop; human
verifies on emulator: intentional button-color change → tier 3 soft fail with correct red
diff overlay; revert → green.

### Session 8 — Proposals, pending state, GitHub adapter
Tasks:
1. Run store: proposals + triage_verdicts tables; runner compares against approved AND open
   proposals → pending outcome (yellow), drift-beyond-proposal → red.
2. VCS adapter interface; GitHub implementation: baseline-only PR creation, the auto-merge CI
   guard (diff touches only visual_baselines + goldens), proposal expiry at release cut.
3. Report: pending section, confirm links deep-linking to the PR.
Acceptance gate: end-to-end on stranger app (human-verified): intended change → proposal →
next run pending not red → confirm → guarded PR auto-merges → next run green, provenance in YAML.

### Session 8.5 — LLM provider abstraction (applens_llm)
Tasks:
1. `LlmProvider` port: complete(LlmRequest) → LlmResult with schema-validated JSON output;
   capabilities() (vision, json-mode, max context). LlmRequest carries system + messages +
   optional images + jsonSchema. All sidecar-facing.
2. ManualProvider (the Phase-1 mode): complete() writes the evidence package to a markdown file,
   prints paste-into-Desktop instructions, blocks until the operator drops a verdict JSON file in
   place, validates it against the schema. This is a real, tested adapter — not a stub.
3. ClaudeProvider on the Messages API (BYO-key) and one more adapter (OpenAI) to prove
   provider-agnosticism; each uses native JSON/tool mode internally, normalizes to AppLens types.
4. Capability-based degradation path (no-vision provider → text tree-diff only) unit-tested with
   a fake provider.
Acceptance gate: the same EvidencePackage produces a schema-valid Verdict through ManualProvider
(human-in-loop, file round-trip) and through a mocked ClaudeProvider, with zero changes to caller
code. Kilo Code / agentic harnesses are explicitly out of scope here (build-time tools, not providers).

### Session 9 — Triage on the provider port
Tasks:
1. Evidence package builder: diff image, tree diff, node meta, commits touching the node's
   module since last green (module map from applens.yaml + package structure).
2. `applens triage` calling the configured LlmProvider (default ClaudeProvider BYO-key; selectable):
   classify bug/intended/flake with cited reasoning; clustering by shared region/causal PR; writes
   proposals and verdicts. Prompt templates live in-repo and are versioned, provider-neutral.
3. Report integration: failures pre-sorted by verdict, cluster cards, overturn-rate metric
   recorded (human decision vs AI verdict).
Acceptance gate: replay Session 8's scenario; triage cites the correct causal commit; a
no-related-commit failure classifies as likely bug. Provider-swap check: same scenario green
through ManualProvider and ClaudeProvider. Determinism check: with triage disabled, run results
are unchanged.

### Session 10 — Crawler + authoring + impact (Phase 4 start)
Tasks:
1. Crawler: budgeted BFS, action prioritization, destructive-action skip list, state clustering
   (route + tree shape) → draft graph PR; rerun mode diffs against approved graph (drift report).
2. `applens author`: test-case text/sheet → draft node/edge/assertion YAML PRs (BYO-key).
3. impact strategy: git diff → modules → nodes → minimal covering paths; wire into the Action.
Acceptance gate: crawler on the stranger app proposes ≥80% of the hand-written graph's nodes;
impact run for a PR touching one screen executes only that screen's paths.

### Session 11 — Dogfood gate (FieldAssist as customer #1)
Not a coding session — an adoption audit. The GT app integrates via pub add + README only.
Every friction point becomes a GitHub issue on AppLens, not a workaround in the app. Patrol
spike happens here if (and only if) a native-flow edge is genuinely blocking: one day to test
NativeAutomator under our harness as a plain dependency; outcome decides the §13 ladder rung.

---

## 4. Standing verification (run at the end of every session)

During Phases 1-2 (before Session 9), triage failures by hand using Claude Desktop as a thinking
aid, and save each as an evidence→verdict pair under docs/triage-evals/. These become the eval
set that validates the automated providers in Session 9. Manual triage now = test data later.


```
melos run analyze && melos run test          # all packages, headless
applens validate examples/stranger_app/qa_graph # graph still sane
git diff --stat docs/                         # spec drift check: if behavior changed, spec changed
```

## 5. Sequencing summary

Sessions 0-5 are Phase 1 (the skeleton) — roughly a month of focused work; nothing else starts
until Session 5's gate passes twice. 6-7 are Phase 2 (oracle depth, applens_compare ships publicly
after 7). 8-9 are Phase 3 (the loop). 10 is Phase 4 (onboarding). 11 is Phase 5 (dogfood).
Naming, pub.dev namespace, and the IP decision happen before Session 0 — they block the first
public commit, not the first private one.
