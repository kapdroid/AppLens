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

### Built + verified on device (golden→green→red→green), then un-shipped

The capture-record flow exists (`applens_record_entry.dart` + the shared
flutter-drive driver content-addressing the captured PNGs). On `emulator-5554`
the full cycle was verified: record `shop.dashboard` → tier-3 **green** →
inject a colour change → **red** (85% diff, diff PNG) → revert → **green**.

> **A golden is device-specific — never ship one as a cross-platform CI
> fixture.** The recorded `shop.dashboard` golden + its `visual_baselines` tag
> were deliberately **reverted** from the committed example: the Gate A nightly
> runs a *different* emulator (Ubuntu, API 34, software-rendered) whose dashboard
> render differs from the API-37 golden, so a committed golden makes the nightly
> red for reasons unrelated to any regression. (This is the exact fragility the
> reviewers flagged and §8 records.) The `applens_entry` host stays tier-3
> *capable* — it loads any bundled `qa_graph/goldens/` and enables
> `MapBaselineSource` — but the example ships none, so tier 3 is inert there and
> the nightly stays device-agnostic green.

To reproduce Gate B on **your** device: run the record command below, add the
emitted `VisualBaseline` to the node, bundle the golden, and run — all on the
*same* device you will re-run on.

```bash
dart run applens_cli:applens run qa_graph \
  --entrypoint integration_test/applens_record_entry.dart -d <your-device>
# → build/applens/goldens/<sha>.png + baselines.manifest.json on the host
```

### The remaining confirmation (human, on the emulator)

The red half — only the deliberate-regression step is left:

```bash
cd examples/stranger_app
# Change a colour on the dashboard (e.g. a button/background), then:
dart run applens_cli:applens run qa_graph --strategy smoke -d emulator-5554
dart run applens_cli:applens report qa_graph build/applens/run.json   # expect exit 1
# revert the colour → next run returns to exit 0.
```

**Acceptance:**
- Green run exits 0 (captures match baselines) — **done**.
- The regression run produces a tier-3 `failedSoft` on `shop.dashboard` and a
  **red diff-overlay PNG** localizing the change (the diff rides `run.json` as
  base64). The same red+diff behaviour is already proven by the headless
  end-to-end test and was observed on-device incidentally; this step is the
  literal confirmation. Reverting returns to green.

A second visual node (an overlay/dialog crop, `crop_to_widget`) is a
nice-to-have that exercises `deriveCaptureScope`'s overlay path on device.
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
