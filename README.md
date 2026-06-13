# AppLens

**Graph-based autonomous QA for Flutter apps.**

> Your app's entire QA knowledge as a versioned, executable graph — tests that
> understand the whole app, not isolated scripts.

AppLens models a Flutter app as a directed graph of UI states: nodes are
equivalence classes of app states, edges are user actions. A path compiler turns
the graph into test plans, a runner walks them on a real app, a tiered oracle
(widget tree → layout hash → scoped pixel diff → advisory) verifies each node,
and an AI sidecar triages failures into *bug* / *intended* / *flake*. The
deterministic core never lets AI decide pass/fail; the single human gate is PR
approval.

- **Open-source core**, Apache-2.0, Flutter-only, CLI-driven.
- Packages live under `packages/` with the `applens_*` prefix.

> **Status: walking skeleton (Phase 1).** Sessions 0–4 are complete (graph model,
> path compiler, first-party action engine, runner loop + run store). Session 5
> lands the CLI, the HTML report, and the GitHub Action; its gate — a real
> emulator running the stranger app's graph green two nights running — is a human
> step. Tier 2/3 oracles, triage, and the crawler come in later phases per
> [`docs/BUILD-PLAN.md`](docs/BUILD-PLAN.md).

## Fifteen-minute walkthrough (the stranger app)

AppLens integrates at **Tier 0** — a dev-dependency only, no production code
touched (ARCHITECTURE.md §10).

```bash
# 0. Tooling (one-time): the CLI scripts run under melos.
dart pub global activate melos

# 1. Add the runner as a dev-dependency of your app, then scaffold:
dart run applens_cli:applens init                 # writes qa_graph/, applens.yaml, integration_test/applens_entry.dart
#    Edit integration_test/applens_entry.dart to launch your app with the
#    AppLens NavigatorObserver installed (two TODOs in the generated file).

# 2. Author or crawl a graph under qa_graph/modules/<module>/nodes/*.yaml,
#    then validate it (fingerprint ambiguity is a hard error):
dart run applens_cli:applens validate qa_graph

# 3. Compile a plan (smoke = tagged-node coverage; regression = every edge):
dart run applens_cli:applens plan qa_graph --strategy smoke --out build/applens/plan.yaml

# 4. Run it on a booted emulator/device (pre-grants permissions, walks the plan,
#    records outcomes to a SQLite run store):
dart run applens_cli:applens run qa_graph --strategy smoke

# 5. Render the static HTML report (exit 0 green / 1 red / 2 pending):
dart run applens_cli:applens report qa_graph build/applens/run.db --out build/applens/report.html
open build/applens/report.html
```

### Navigating a large graph

You read the graph through generated views, never by browsing files (§5):

```bash
applens graph stats qa_graph                 # counts, orphans, per-module health
applens graph find  qa_graph --tag sanity    # query instead of scroll
applens graph path  qa_graph shop.dashboard shop.confirm
applens graph show  qa_graph shop            # render a module subgraph to HTML
```

A failure in the report is **self-locating**: it carries the node's file path and
assertion locus (`modules/shop/nodes/cart.yaml:payload.assertions[0]`) and a
rendered subgraph with the failing node highlighted — you never search the others.

## CI

Use [`actions/applens-run`](actions/applens-run/action.yml) (validate → plan →
run → report → upload), driven by an emulator. The
[`nightly`](.github/workflows/nightly.yaml) workflow boots an Android emulator
and runs the stranger app's graph; green two consecutive nights is the
walking-skeleton gate.

## Layout

```
packages/
  applens_core/      graph model, validation, path compiler, run store, VCS port
  applens_runner/    orchestrator, oracle tiers, DriverInterface, action engine  [Flutter]
  applens_compare/   standalone tolerant golden comparator                       [Flutter]
  applens_sdk/       optional in-app: TestClock, introspection                   [Flutter]
  applens_llm/       LlmProvider port + adapters
  applens_crawler/   exploration engine, draft-graph generation
  applens_report/    static HTML report + graph render engine
  applens_cli/       init · validate · plan · run · report · graph
examples/
  stranger_app/      demo Flutter app + qa_graph; the zero-special-access proof
docs/                ARCHITECTURE.md · BUILD-PLAN.md · SCAFFOLD.md · review protocol
```

## Developing

```bash
dart pub get && dart pub global activate melos
melos run ci     # format-check → analyze → boundaries → tests (headless)
```

See [`CLAUDE.md`](CLAUDE.md) for the project constitution and [`docs/`](docs/) for
the binding design.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
