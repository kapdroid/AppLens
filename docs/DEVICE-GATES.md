# Device gates — the human-verified runbook

Two acceptance gates require a real emulator and so are human checkpoints
(CLAUDE.md "Human checkpoints"). Their *logic* is proven headless; these runs
are confirmation, not discovery. Run them deliberately rather than deferring to
release — clearing this debt early keeps the back half of the plan honest.

| Gate | Session | What it proves | Ready to run? |
|------|---------|----------------|---------------|
| **A — Nightly walking skeleton** | 5 | The full `run → report` pipeline is green on a real emulator, two consecutive nights in CI | **Yes, now** |
| **B — Tier-3 red diff** | 7 | A visual regression produces a red diff and a revert returns to green | Needs the `baseline record` capture flow (below) |

---

## Gate A — Nightly walking skeleton (Session 5)

The headless slice already ran green on a real emulator (commit `298717e`,
`docs/WALKING-SKELETON.md`). This gate is the *automated* re-confirmation:
`.github/workflows/nightly.yaml` boots an Android emulator (API 34, x86_64,
KVM) and runs the plan on it nightly at 03:00 UTC.

**Acceptance:** the `AppLens Nightly (stranger app)` workflow is **green two
consecutive nights** (BUILD-PLAN §3).

### Run it now (don't wait for the schedule)

1. On GitHub: **Actions → AppLens Nightly (stranger app) → Run workflow**
   (`workflow_dispatch`). Do this once today and once tomorrow — or twice with a
   gap — to satisfy the two-nights rule.
2. Each run must finish green. The job:
   - boots `emulator-5554`,
   - `dart run applens_cli:applens run qa_graph --strategy smoke --device emulator-5554`
     → walks the graph via `flutter drive`, writes `build/applens/run.json`,
   - `dart run applens_cli:applens report qa_graph build/applens/run.json`
     → exit 0, uploads `applens-nightly-report`.
3. Download the `applens-nightly-report` artifact; the report HTML should show
   every visited node **passed**, no red.

### Reproduce locally (optional, faster feedback)

```bash
cd examples/stranger_app
# with an emulator already booted as emulator-5554:
dart run applens_cli:applens run qa_graph --strategy smoke --device emulator-5554
dart run applens_cli:applens report qa_graph build/applens/run.json \
  --out build/applens/report.html   # exit 0 = green
```

Expected: the run walks `shop.dashboard → catalog → product` (scrolling
`product_40` into view), every tier-1 assertion holds, `report` exits 0.

---

## Gate B — Tier-3 red diff (Session 7)

Everything *headless* is built and reviewed: the tolerant comparator
(`applens_compare`), capture (`capture.dart`, PNG-native), scope derivation,
the tier-3 evaluator, the orchestrator wiring (all three tiers, cheap-to-
expensive), and the baseline storage layer (`baselineImageKey`,
`IoBaselineSource`, `MapBaselineSource`). What remains before this gate is
runnable on a device:

### Remaining build (next chunk)

1. **Tag two stranger nodes** with a `visual_baselines` entry — one a route
   (`shop.product`, full-screen) and one an **overlay** (a confirm dialog,
   crop-to-anchor). The dialog node's anchor must be the dialog's own keyed
   root, so the crop clears the modal barrier.
2. **`applens baseline record qa_graph --device emulator-5554`** — a capture
   pass that walks to each tagged node, captures its scope (`deriveCaptureScope`)
   via the device's live binding, returns the PNGs to the host (through
   `binding.reportData`, like `run.json`), writes them to
   `qa_graph/goldens/<hex>.png` (`baselineImageKey`), and emits the
   `VisualBaseline` YAML to add to each node (`state: approved` for the
   example's intentional fixtures; in a real app this is a proposal the human
   approves via PR — §9).
3. **Bundle the goldens as assets** so the on-device run loads them through
   `MapBaselineSource` (the device counterpart of `IoBaselineSource`), the same
   way the graph is bundled via `MapGraphFiles`.

### The gate itself (human, on the emulator)

Once the above exists:

```bash
cd examples/stranger_app
# 1. Baseline run — both tagged nodes match → green.
dart run applens_cli:applens run qa_graph --strategy smoke --device emulator-5554
dart run applens_cli:applens report qa_graph build/applens/run.json   # exit 0

# 2. Introduce a regression: change the confirm button's color in the app.
#    Re-run.
dart run applens_cli:applens run qa_graph --strategy smoke --device emulator-5554
dart run applens_cli:applens report qa_graph build/applens/run.json   # exit 1 (soft fail)
```

**Acceptance:**
- Step 1 is green (captures match baselines).
- Step 2 produces a tier-3 `failedSoft` on the changed node, and the report
  shows a **red diff-overlay PNG** localizing the color change (the diff
  artifact rides `run.json` as base64).
- Reverting the color change and re-running returns to **green**.

This exercises the whole tier-3 path on real hardware at device DPR — the one
thing the headless harness can't confirm (the mobile-platform reviewer's
logical-vs-device-resolution flag, ARCHITECTURE §8).

---

## Why these are deferred, not skipped

BUILD-PLAN §3 says no Phase 2 work starts until Gate A passes; the lead
consciously deferred it to keep building Sessions 6–7 while the on-device walk
was already proven once. That is tracked debt, recorded here so it is retired
deliberately — ideally Gate A now (it is ready) and Gate B as soon as its
capture flow lands — not silently carried to release.
