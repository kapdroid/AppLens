# Walking-skeleton handoff (Session 5 gate)

The headless spine of Session 5 is built and green (`melos run ci`): the CLI
(`validate`/`plan`/`graph`/`report`/`init`/`run`), the HTML report + graph render
engine, `WidgetFingerprintSource`, the GitHub Action, and the nightly workflow.

**On-device run: PASSING.** `flutter test integration_test/applens_entry.dart -d
emulator-5554` is green on a real Android emulator (API 37): AppLens loads the
graph from bundled assets, compiles the smoke plan, walks the real StrangerApp
(dashboard + catalog match and pass), and scrolls `product_40` into the long
list. The graph-bundling, app-id, and device-targeting blockers are closed.

**The gate is still not fully met.** Session 5's acceptance gate (BUILD-PLAN §3)
also requires the **nightly workflow green two consecutive nights in GitHub
Actions** — that needs a real repo + CI runs, the remaining human checkpoint.

## Open blockers before the gate can pass (from the mobile-platform review)

These were cited with `file:line`; the device-design ones are fixed, the rest
need a device to close:

1. **stranger entrypoint + graph reconciliation — DONE, proven headless.**
   `examples/stranger_app/integration_test/applens_entry.dart` (device variant)
   and `test/walking_skeleton_test.dart` (headless) now walk the smoke plan
   end-to-end against the real app; the app declares the AppLens dev-deps and an
   `applens.yaml`. The graph was reconciled with v1: every Scaffold AppBar got
   `Key('app_bar')` (so the shared-fragment anchor matches), and smoke coverage
   was retagged onto flag-free nodes (`dashboard`, `catalog`) because v1 does not
   yet observe flags — `shop.cart`'s `cart_count > 0` identity needs SDK
   introspection (a later session), so it stays out of smoke for now.
   `flutter test test/walking_skeleton_test.dart` passes: dashboard + catalog
   matched/passed and `product_40` scrolled into the long list. **The remaining
   step is running the same walk on a real emulator** via
   `flutter test integration_test/applens_entry.dart -d <device>`, which needs
   the app's Android platform folder (`flutter create --platforms=android .`).
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
nights running. Until that CI evidence holds, **no Phase 2 work starts.**

## Status

- ✅ On-device walk green on emulator-5554.
- ✅ **`applens run` → `report` works end-to-end on device.** `applens run
  qa_graph --device emulator-5554` uses `flutter drive` to walk the app on the
  device; the entrypoint returns the run via `binding.reportData` and
  `test_driver/integration_test.dart` writes `build/applens/run.json` on the
  host; `applens report qa_graph build/applens/run.json` renders green HTML
  (exit 0). No `adb pull`, no on-device SQLite — the canonical integration_test
  data path supersedes the earlier sqlite3_flutter_libs/run.db-pull plan.
- ◻ **Nightly green two consecutive nights in real GitHub Actions** — the last
  gate item; needs a real repo (human task). Update `nightly.yaml` to run
  `applens run` via the emulator-runner and `applens report` the resulting
  `build/applens/run.json`.
- ◻ iOS `simctl` pre-grant path; `settle()` hardening for continuous animations
  (Android-first is fine for v1).
