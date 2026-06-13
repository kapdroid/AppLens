# AppLens

**Graph-based autonomous QA for Flutter apps.**

> Your app's entire QA knowledge as a versioned, executable graph — tests that
> understand the whole app, not isolated scripts.

AppLens models a Flutter application as a directed graph of UI states: nodes are
equivalence classes of app states, edges are user actions. A path compiler turns
the graph into test plans, a runner walks them on a real app, a tiered oracle
(widget tree → layout hash → scoped pixel diff → advisory) verifies each node,
and an AI sidecar triages every failure into *bug* / *intended* / *flake*. The
deterministic core never lets AI decide pass/fail; the single human gate is PR
approval.

- **Open-source core**, Apache-2.0, Flutter-only, CLI-driven.
- Packages live under `packages/` with the `applens_*` prefix.

> **Status: Session 0 (scaffold).** This is the founding skeleton — the package
> topology, contracts, lints, boundary enforcement, and CI are in place; the
> features described above are built session by session per
> [`docs/BUILD-PLAN.md`](docs/BUILD-PLAN.md). The fifteen-minute walkthrough
> README lands with the walking skeleton (Session 5).

## Layout

```
packages/
  applens_core/      graph model, schema, validation, path compiler, VCS port
  applens_runner/    orchestrator, oracle tiers, DriverInterface, action engine  [Flutter]
  applens_compare/   standalone tolerant golden comparator                       [Flutter]
  applens_sdk/       optional in-app: TestClock, introspection                   [Flutter]
  applens_llm/       LlmProvider port + adapters
  applens_crawler/   exploration engine, draft-graph generation
  applens_report/    static HTML report generation
  applens_cli/       init, validate, plan, run, report — composition root
examples/
  stranger_app/      demo Flutter app; the permanent zero-special-access proof
docs/                ARCHITECTURE.md · BUILD-PLAN.md · SCAFFOLD.md
```

## Developing

```bash
dart pub get                    # resolves the whole workspace
dart pub global activate melos  # one-time: puts `melos` on PATH
melos run ci                    # format-check → analyze → boundaries → tests (headless)
```

See [`CLAUDE.md`](CLAUDE.md) for the project constitution (the rules every change
must respect) and [`docs/`](docs/) for the binding design.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
