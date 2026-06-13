# Walking-skeleton handoff (Session 5 gate)

The headless spine of Session 5 is built and green (`melos run ci`): the CLI
(`validate`/`plan`/`graph`/`report`/`init`/`run`), the HTML report + graph render
engine, `WidgetFingerprintSource`, the GitHub Action, and the nightly workflow.

**The gate is not yet met.** Session 5's acceptance gate (BUILD-PLAN §3) is the
walking skeleton: *a human runs the README on the stranger app, and the nightly
workflow is green two consecutive nights in GitHub Actions, with one node
scrolling into a long list.* That needs a real emulator/device and a real GitHub
repo — it is the human checkpoint, and the constitution forbids inventing device
results.

## Open blockers before the gate can pass (from the mobile-platform review)

These were cited with `file:line`; the device-design ones are fixed, the rest
need a device to close:

1. **stranger entrypoint + graph reconciliation (the big one).** The stranger app
   has no `integration_test/applens_entry.dart` and no `applens_runner` dev-dep,
   so the nightly has nothing to run. Adding them also requires reconciling the
   graph with v1's capabilities:
   - The `shop.dashboard` node's identity includes anchor `app_bar` (from the
     shared fragment), but the app has no widget keyed `app_bar` — add
     `key: const Key('app_bar')` to each Scaffold's AppBar, or drop it from
     identity.
   - The `shop.cart` node's identity requires flag `cart_count > 0`, but v1 does
     **not** observe flags (SDK introspection is the Tier-1 SDK, a later session).
     Until then, a flag-gated node can never match. For the v1 skeleton, retag
     smoke coverage onto flag-free nodes (e.g. `dashboard`, `catalog`) or model a
     `cart_empty` node, so the smoke plan walks a path the runner can actually
     match.
2. **On-device graph/plan bundling + `run.db` transfer.** `loadGraph('qa_graph')`
   and `SqliteRunStore.open('build/applens/run.db')` use host paths; under
   on-device `integration_test` the app process can't read host files and writes
   `run.db` on the device. Bundle the compiled plan as a test asset (or report
   results to the host via `IntegrationTestWidgetsFlutterBinding`), and `adb pull`
   the run store before `applens report`.
3. **`sqlite3` on device.** The run store uses `sqlite3` (system FFI). On a real
   device the app must bundle the native lib — add `sqlite3_flutter_libs` to the
   app, or have the host (not the device) own the SQLite write.
4. **`settle()` on device.** `pumpAndSettle()` returns under fake time in
   `flutter test` but polls real frames on-device — it will time out on any
   continuous animation. The bounded settle + `FrameStabilizer` wiring (built,
   unit-tested) needs hooking up with `timeDilation` pinning (the determinism kit).
5. **iOS.** Pre-granting is Android-only (`adb pm grant`). iOS needs
   `simctl privacy grant` and has no `adb`; the `run` command has no iOS branch yet.

Fixed at the design level (no device needed, verified via `--dry-run`):
`applens run` now targets the device (`flutter test -d <device>`) and pre-grants
with the real `app_id` from `applens.yaml` (was an unfilled `<applicationId>`,
print-only); the nightly/action pass the device id.

## Commands for the human (once a device is available)

```bash
# Local, against the stranger app, on a booted emulator:
cd examples/stranger_app
dart run applens_cli:applens init                          # if not already scaffolded
# ... reconcile the graph + entrypoint per blockers 1–4 above ...
flutter emulators --launch <id> && adb wait-for-device
dart run applens_cli:applens validate qa_graph             # expect: ✓ valid
dart run applens_cli:applens run qa_graph --device emulator-5554
adb pull /data/.../build/applens/run.db build/applens/run.db   # per blocker 2
dart run applens_cli:applens report qa_graph build/applens/run.db --out build/applens/report.html
open build/applens/report.html                             # expect: green, 1 node scrolled a long list
```

Expected: `validate` exits 0; `run` walks the smoke plan on the device; `report`
exits 0 (green). Then push and watch `.github/workflows/nightly.yaml` go green two
nights running. Until all of the above holds, **no Phase 2 work starts.**
