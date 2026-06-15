# AppLens — Graph-Based Autonomous QA for Flutter
### Founding Architecture Specification (v0.1 draft)

*Name: **AppLens** (packages under the `applens_*` prefix; verify pub.dev namespace availability before first publish). Open-source core (Apache-2.0), Flutter-only, engineering-lead-first, CLI-driven.*

---

## 1. Vision and positioning

AppLens models a Flutter application as a directed graph of UI states. Nodes are equivalence classes of app states; edges are user actions. The graph is executable: a path compiler turns it into test plans, a runner walks those plans on a real app, a tiered oracle verifies each node, and an AI sidecar triages every failure into *bug*, *intended change*, or *flake* — with exactly one human decision point in the whole system: PR approval.

The one-line pitch: **your app's entire QA knowledge as a versioned, executable graph — tests that understand the whole app, not isolated scripts.**

What makes this different from everything currently on the market:

The graph model itself — no Flutter tool ships whole-app model-based testing. Existing options are component-level golden tests (no flows), Maestro/Patrol scripts (linear flows, no app model, no coverage notion), or cloud visual-diff platforms (web-centric, no mobile depth). AppLens gives node/edge coverage as a first-class release metric.

White-box depth — because AppLens runs in-process with the Flutter widget tree, its primary oracle is the tree, not pixels. Cheap, deterministic, and impossible for black-box competitors (Maestro, Appium-based tools, VLM startups) to replicate.

Repo-aware AI triage — AppLens correlates a failed node with the commits that touched its module since the last green run. "Button color changed; PR #482 modified order_button.dart; likely intended" is a verdict no screenshot vendor can produce, because they don't have repo context. AppLens asks for it as a first-class feature.

Test impact analysis from the graph — given a git diff, AppLens maps changed files → modules → affected nodes → the minimal path set that covers them. PR-time runs test only what the PR could have broken; nightly runs test everything.

A single human gate — every mutation (graph structure, baselines, fixes) flows through a PR. AI proposes, applies, and merges guarded changes; a human approves. Testing is never blocked by pending decisions (see §9, proposed-baseline state).

Deterministic core, advisory AI — same graph + same seed = same result, always. AI never gates pass/fail.

---

## 2. System overview

```
            ┌─────────────────────────────────────────────────┐
            │                APPLENS (OSS, Apache-2.0)          │
            │                                                 │
  QA cases ─┤► AI authoring*──► Graph model (YAML, customer   │
  Crawler ──┤                    repo, versioned with code)   │
            │                         │                       │
            │                   Path compiler                 │
            │            (coverage / impact / tags)           │
            │                         │                       │
            │                  Run orchestrator               │
            │     (node matcher, determinism kit, capture)    │
            │                         │                       │
            │              Tiered oracle engine               │
            │   T1 widget tree → T2 layout hash → T2.5 semantic │
            │      → T3 scoped golden → T4 advisory            │
            │                         │                       │
            │              ── DriverInterface ──              │
            │        (first-party engine; native: Phase 3)    │
            │                         │                       │
            │            Run store → Report (HTML/CI)         │
            └──────────────┬──────────────────────────────────┘
                           │ evidence packages, proposals
            ┌──────────────▼──────────────────────────────────┐
            │   AI SIDECAR (* OSS bring-your-own-key local    │
            │   mode; hosted cloud adds clustering, history,  │
            │   team review)                                  │
            │   triage · clustering · authoring · healing     │
            └──────────────┬──────────────────────────────────┘
                           │ PRs (the single human gate)
                     VCS adapter (GitHub v1)
```

Everything above the DriverInterface is owned IP. The driver layer is rented (Patrol/integration_test) and swappable. The app under test integrates via tiered SDK (§10): useful at near-zero integration, better with the SDK.

---

## 3. Repository layout

Monorepo, all-Dart where possible (contributors are Flutter developers; pub is the distribution channel):

```
applens/
  packages/
    applens_compare/     # standalone: tolerant AA-aware GoldenFileComparator
                       # for plain flutter_test goldens (2-line adoption) —
                       # the OSS wedge; usable with zero AppLens knowledge
    applens_core/        # graph model, schema, validation, path compiler
    applens_runner/      # orchestrator, oracle tiers, DriverInterface,
                       # first-party action engine, determinism kit
    applens_sdk/         # optional in-app package: TestClock, introspection
                       # service extension, seed hooks
    applens_cli/         # init, crawl, validate, plan, run, report, baseline
    applens_crawler/     # exploration engine, draft-graph generation
    applens_llm/       # LlmProvider port + adapters (Claude, OpenAI, Gemini,
                       # local, ManualProvider); provider-agnostic, schema-validated
    applens_report/      # static HTML report generator
  actions/
    applens-run/         # GitHub Action (v1 VCS target)
  docs/
  examples/
    stranger_app/      # an OSS demo Flutter app wired up end-to-end —
                       # the permanent proof of zero-special-access integration
```

Not in this repo, ever: the hosted AI service internals, and anything FieldAssist-specific. FieldAssist (customer #1) integrates exclusively through the public interface — `dart pub add`, YAML, CLI — and keeps its graph in its own repo under `qa_graph/`.

Customer-side layout (created by `applens init`):

```
their_app/
  qa_graph/
    applens.yaml             # tool config: device profiles, locales, tiers, permissions
    modules/                 # mirrors the app's module structure (see §5)
      <module>/
        <module>.module.yaml # manifest: owner, tags, entry nodes
        nodes/*.yaml         # one node per file
        flows/*.flow.yaml    # named human-authored sequences
    shared/
      overlays/*.yaml        # dialogs/banners composed into many nodes
      fixtures/              # seed-data references
    goldens/                 # golden PNGs (Git LFS recommended)
    masks/*.yaml             # dynamic-region masks, widget-key based
    paths/*.yaml             # compiled plans (generated, optionally committed)
  integration_test/
    applens_entry.dart       # generated runner entrypoint
```

Humans navigate this through `applens graph` commands and the failure report's self-locating paths, not by browsing files directly (see §5).

---

## 4. Graph model

A node is an equivalence class of app states, defined by an explicit abstraction: identity metadata says how the runner recognizes the node at runtime; payload metadata says what to do and verify there. Execution history is never stored in the node — it belongs to the run store.

```yaml
id: order_screen.cart_filled
identity:
  route: /order
  anchors: [btn_place_order, list_cart_items]   # widget keys that must exist
  flags: { cart_count: ">0" }                   # via SDK introspection (tier 1)
  overlay: false                                # true for dialogs/sheets
payload:
  assertions:
    - { type: widget_exists, key: btn_place_order }            # tier 1
    - { type: text_equals, key: lbl_total, source: computed }  # tier 1
    - { type: layout_hash, baseline: hashes/order_filled }     # tier 2
  visual_baselines:                                            # tier 3, tagged nodes only
    - context: { device: pixel6, locale: en, theme: light }
      capture: crop_to_widget          # derived: full_screen | crop_to_widget | region
      widget: card_order_summary
      image: sha256:9f3a...            # content-addressed, LFS
      mask: masks/order_screen.yaml
      threshold: 0.002
      state: approved                  # approved | proposed | rejected
      approved_by: <user>
      reason_pr: repo#482
      replaced: sha256:7c1d...         # audit trail
  edges:
    - { action: tap, key: btn_place_order, target: order_confirm }
    - { action: back, target: dashboard }
  guards: { requires: [journey.started] }
  tags: [order_flow, sanity]
  owner: team-checkout
```

Edge actions in v1: tap, long_press, enter_text, scroll_to, swipe (carries a `direction:` — up/down/left/right — flung from the screen centre or a keyed widget), back, deep_link (delivered in-process via the navigation `pushRoute` message, so the app's own Router/Navigator routes it — no Patrol), and native (declared but **not driven** in v1: permission dialogs are eliminated by pre-granting from `applens.yaml`, not automated; Patrol-mediated dialogs/notifications are Phase 3). Each edge may carry its own preconditions and a settle policy.

`applens validate` runs static analysis on the whole graph before any execution: schema validity; fingerprint ambiguity (two nodes whose identity sets are not mutually distinguishable — a hard error, the most important check in the system); reachability (every node reachable from declared entry nodes); orphan baselines; dangling edge targets; guard satisfiability. A graph that validates is guaranteed matchable at runtime.

---

## 5. Graph at scale — navigability, comprehension, debugging

A large app produces a large graph (an app the size of a mature GT app realistically yields 800-1500 nodes). A flat folder of that many YAML files is unusable, so scale is a first-class design concern, not an afterthought. The governing principle: **YAML is the source of truth for machines; a generated, queryable, visual view is the source of truth for humans.** Humans rarely read raw node files — they read views compiled from them, the same way one reads a rendered design rather than its binary. A thousand files nobody opens by hand is fine; the failure mode is forcing a human to scroll them.

Three distinct problems, three distinct solutions:

**Physical sprawl — mirror the app's modules.** The graph directory mirrors the app's own module structure, because that is the mental model the team already holds:

```
qa_graph/
  modules/
    order/
      order.module.yaml      # manifest: owner, tags, entry nodes
      nodes/                  # one node per file
        cart_filled.yaml
        confirm.yaml
      flows/
        place_order.flow.yaml # named human-authored sequences
    payment/
    journey/
  shared/
    overlays/                 # dialogs/banners reused across modules
    fixtures/                 # seed-data references
```

"1000 files" becomes "~60 modules averaging ~15 nodes." A developer touching the order screen opens `modules/order/` and sees only the ~15 relevant nodes. Module folders mirror code modules, so ownership and the impact-analysis file→module→node mapping fall out for free. Decision: one node per file (clean git diff and blame at scale) rather than one file per module — tooling makes the file count irrelevant, and diff clarity wins.

**Comprehension — the `applens graph` command family.** The graph is treated as a queryable database with the YAML as its serialization. Humans interact through generated views, never by browsing files:
- `applens graph show <module>` — renders a module's subgraph visually (nodes + edges) in the browser, compiled from the YAML, using the same render engine as the report.
- `applens graph find --tag sanity --owner <team>` — query instead of scroll.
- `applens graph path <a> <b>` — show how two nodes connect.
- `applens graph stats` — node/edge counts, orphans, per-module coverage and health.

This is the most important piece: the graph being in files does not mean humans read files.

**Debugging — every failure is self-locating.** The "which of 1000 nodes broke?" fear only exists if the report makes a human search. It must not. A failure carries the exact path and locus — `modules/order/nodes/confirm.yaml:assertions[2]` — clickable straight to the node and assertion, plus a rendered subgraph showing the failing node in red among its neighbors. The other 999 nodes are never seen. Debugging a 1000-node graph should feel identical to debugging a 50-node graph, because only the one failing node is ever touched; if it does not feel that way, the report is wrong, not the graph size.

Two structural rules that keep large graphs maintainable:

**Hierarchical IDs as namespace.** Node IDs are globally unique and encode location: `order.confirm`, `payment.upi.pending`. An ID in a failure report reveals the file path without a lookup; fingerprint-ambiguity validation guarantees uniqueness.

**Composition over repetition.** Shared UI (app bar, sync banner, common dialogs) appears on hundreds of screens. Nodes include shared fragments rather than copying them: `includes: [shared/overlays/sync_banner]`. One definition referenced everywhere — an app-bar change is one edit, not two hundred. This is what prevents the file count from becoming an equal-sized maintenance burden. Most nodes are crawler-generated and machine-managed; humans review them in module-sized PR diffs and edit assertions, rarely authoring a node from scratch.

---

## 6. Path compiler

Input: the validated graph plus a strategy. Output: an ordered, human-readable plan (`paths/*.yaml`) the runner executes — deliberately Maestro-flavored so a developer can read what will happen without running anything.

Strategies, in increasing cost:

**smoke** — node coverage of tagged nodes (`@sanity`): visit every tagged node at least once via shortest paths. Minutes, runs on every PR.

**impact** — the differentiator. Given `--diff <base>..<head>`: changed files → module mapping (from the app's package structure plus an optional explicit map in applens.yaml) → nodes owned by those modules → minimal path set covering those nodes *and every edge into them*. PR-time testing that scales with the change, not the app.

**regression** — full edge coverage. Computed as a Eulerian-path approximation (directed Chinese-postman heuristic; optimality is not required, determinism is). Nightly.

**soak** — randomized long walks with a fixed seed, weighted toward low-visit-count edges. Finds the bugs nobody wrote a case for; fixed seed keeps every run reproducible.

The compiler also precomputes, for every node, its top-k alternate inbound paths — consumed by the runner's reroute logic on hard failures (§7). Plans embed the graph content hash they were compiled from, so a stale plan against a changed graph is rejected at run start.

---

## 7. Runner and orchestrator

The runner executes a plan node by node. Its responsibilities, in order per step: perform the edge action through DriverInterface, stabilize, fingerprint the resulting state, match it to the expected node, execute the oracle tiers, capture artifacts, record the visit, choose the next step (or reroute).

**DriverInterface** is the ownership boundary — roughly ten methods, defined day one, with a hard rule that nothing above it imports Patrol directly:

```dart
abstract class AppLensDriver {
  Future<void> tap(WidgetSelector s);
  Future<void> longPress(WidgetSelector s);
  Future<void> enterText(WidgetSelector s, String text);
  Future<void> scrollTo(WidgetSelector s);
  Future<void> swipe(SwipeDirection direction, {WidgetSelector? on});
  Future<void> back();
  Future<void> openDeepLink(Uri uri);
  Future<WidgetTreeSnapshot> tree();          // serialized element tree
  Future<Capture> capture(CaptureScope scope); // full / widget-cropped / region
  Future<void> settle({SettlePolicy policy});
  Future<void> native(NativeAction a);         // permissions, dialogs (Patrol)
}
```

v1 ships a **first-party action engine** implementing this interface directly on Flutter SDK APIs — element-tree lookup, hit-test verification before every tap (refusing to tap obscured widgets, with our own diagnostics), synthetic pointer sequences into `GestureBinding` for tap/long-press/swipe, physics-respecting repeated drags for `scrollTo`, IME-channel emulation (`TestTextInput`) for `enterText` (text is never pointer events), the root `Navigator.maybePop` for in-Flutter back (the public equivalent of the `@protected` `handlePopRoute`, and it honours `PopScope`; on-device back fidelity is revisited at Session 5). These are public, Google-maintained APIs that ship with every Flutter version — in-process tree access is non-negotiable for the oracle tiers, and owning this layer buys our selector grammar, fused settle policy, and per-action tree snapshots for fingerprinting, at the cost of ~400 lines over stable SDK surface (scroll edge cases — nested scrollables, slivers — are where the testing budget goes; the skeleton's five nodes deliberately include one scroll-into-long-list edge).

`native()` is **unimplemented in v1**. Permission dialogs are eliminated rather than automated: `applens.yaml` declares a `permissions:` list and the CLI pre-grants them at session start (`adb shell pm grant` / `simctl privacy grant`), so the dialogs never appear in CI. The flows pre-granting cannot fake (mid-flow pairing prompts, biometric sheets, tapping a real push notification) are Phase 3 surface, gated on a one-day spike: confirm Patrol's native bridge (gRPC server APK + `NativeAutomator` client) runs under our harness as a plain `pub` dependency without adopting `patrolTest`. Likely yes; if not, escalate the dependency ladder (§14) one rung at a time. Tier 0 integration therefore depends on nothing outside the Flutter SDK — which is what makes the fifteen-minute onboarding claim defensible.

**Node matching.** After every action the runner computes the live fingerprint — current route (from a generated NavigatorObserver in the entrypoint), anchor-key probe against the tree, and flags (via SDK introspection when present, UI inference otherwise) — and matches it against the expected node. Match → proceed. Mismatch against expected but match against *some* node → unexpected-transition event (often the most interesting bug class: the app went somewhere legal but wrong). No match at all → hard failure.

**Determinism kit.** Before any oracle: animations disabled (timeDilation pinned through the binding), pumpAndSettle with a bounded frame budget, then frame stabilization — capture is retried until two consecutive frames are byte-identical (bounded retries; a screen that never stabilizes is its own failure, "node won't settle," not a pixel diff) — keyboard dismissed unless the node declares keyboard-up, clock frozen via SDK TestClock when integrated, fixed device profile per baseline context, fixed locale/theme injection. Without the kit, no visual tier is allowed to run — the runner enforces this rather than documenting it.

**Failure semantics.** Four node outcomes:

`failed_soft` — an assertion mismatched but navigation works: mark red, attach evidence, continue the path. `failed_hard` — the expected node is unreachable: consult precomputed alternates, attempt reroute to keep downstream nodes testable; record the broken edge. `blocked` — genuinely unreachable after reroute attempts: distinct from failed in every report (an untested node is not a broken node). `pending` — mismatches the approved baseline but matches an open proposal (§9): yellow, quiet, never blocks the run.

On every failure regardless of tier, the runner captures a full-screen screenshot, the serialized tree, and recent app logs as run artifacts — evidence for humans and triage, never compared against anything.

---

## 8. Oracle tiers

Executed cheap-to-expensive per node; a tier-1 structural failure short-circuits lower tiers by default (configurable to capture-all for full damage reports).

**Tier 1 — widget tree (the workhorse).** Key existence, text equality/regex, list counts, enabled/disabled state, semantic properties. Deterministic, no baselines to maintain, catches the large majority of functional regressions. This tier is why in-process execution is non-negotiable.

**Tier 2 — layout hash.** A normalized hash of the tree's *shape* (widget types, depths, relative geometry buckets) with all data values stripped. Catches "the screen's structure broke" with zero sensitivity to data, and costs one string per node in the YAML.

**Tier 2.5 — semantic diff (text + geometry; recorded nodes only).** Between the whole-tree hash and the pixels: a content-addressed baseline snapshot of each identifiable widget — its key (or, for unkeyed widgets, its `(type, text)`), plain text, and bounds normalized to the screen's largest box (0..1, DPR-independent). A run captures the live snapshot the same way and diffs it: matched by the layered identity scheme — by key first, then by a *unique* `(type, text)` for unkeyed widgets, leaving genuinely ambiguous widgets unmatched (reported, never force-paired) — then each pair is checked for a text change (exact) and a geometry drift beyond a normalized tolerance (default 0.02, absorbing antialiasing/sub-pixel jitter like the tier-3 threshold). A node opts in by carrying a `structural_baselines` entry; an optional `watch` hint scopes *which* widgets and dimensions (`keys`, `text`, `layout`) are diffed (absent ⇒ track every identifiable widget, both dimensions). Findings are deterministic and gate exactly like the other tiers (`failedSoft`, overturnable by a proposal); AI never enters the verdict. Its value over tiers 1–3: it catches an *alignment/position* change pixels-blindly (which tier 1 cannot express and the layout hash only coarsely buckets) and a text change on a widget no explicit `text_equals` covers, and — uniquely — it **localizes** the failure. The evidence artifact is an annotated screenshot: a labeled bounding box per finding (`"Start shopping" → "Start"`, `moved`), drawn by the standalone `applens_compare` annotator (pixel boxes, zero AppLens-model knowledge) from the findings' normalized bounds scaled to the capture. Recorded snapshots live in `qa_graph/structural/<hex>.json`, content-addressed like goldens, loaded behind a `StructuralBaselineSource` seam (host filesystem or bundled assets). Because it runs cheaper than tier 3 and short-circuits it, a watched semantic regression is reported with its localized box before the costlier whole-screen pixel diff runs.

**Tier 3 — scoped pixel comparison / goldens (tagged nodes only).** Deterministic pixel comparison, decided design: stabilized capture → widget-key masks applied to both images → vendored pixelmatch algorithm (Dart port of mapbox/pixelmatch, ISC: YIQ perceptual color distance + anti-aliasing detection that excuses edge pixels whose difference is explained by neighbors) → dual thresholds: per-pixel YIQ tolerance (default 0.1) and overall diff ratio over unmasked pixels (default 0.001), both overridable per node, defaults recalibrated from the first weeks of real skeleton runs. Output per comparison: ratio, verdict, red diff-overlay PNG to the run store. No AI in the verdict, ever — triage interprets downstream. Capture scope is *derived* from the node's identity, not hand-chosen per baseline: an overlay node (dialog/sheet/snackbar) crops to its anchor widget's painted bounds — keyed, so the crop survives layout shifts, and because the anchor resolves to the overlay's own keyed root (never the unkeyed modal barrier), the crop stays clear of the barrier that a naive before/after tree-diff would mistake for the captured surface; a route node captures full screen; a small curated set of composition-critical screens pins full_screen via a tag. In-place region changes are left to tiers 1–2 — a tagged node is captured whole or as its overlay widget, never as an ad-hoc sub-rect. Mechanically, capture renders the root repaint boundary to a PNG (straight alpha) and crops the decoded image to the widget's `tester.getRect` **scaled by the device pixel ratio**, rather than rasterizing a sub-rect layer (which deadlocks the headless test binding). The capture is at the device's **physical resolution** (the PNG is `logical × devicePixelRatio` pixels, and the crop scales `getRect` — which is logical — by the same ratio so it lands on the widget's pixels at any DPR): one profile per (node, device, locale, theme), so a golden is keyed to its device and is deterministic and comparable across runs *on that device*. Cross-device pixel fidelity is out of scope for v1 — the (node, device, locale, theme) baseline key already reflects that a golden is device-specific. Masks are widget-key based (resolved to rects at capture time) so they survive layout shifts. Baselines are keyed by (node, device, locale, theme) and content-addressed. Implementation is split for reuse (Session 6 decision, §14 dependency ladder — duplicating the algorithm into the runner would be a banned fork). The pure algorithm and tolerant comparator live in the **standalone `applens_compare` package**: `pixelmatch.dart` (pure algorithm, validated byte-for-byte against the upstream JS test fixtures — tests ported first, algorithm second), `comparator.dart` (masks, thresholds, verdict), and the `AppLensGoldenFileComparator` golden-compat slot. `applens_runner` depends on `applens_compare` and reuses it; `applens_runner/lib/src/visual/` holds only the device-coupled glue: `capture.dart` (stabilization, scoped capture, mask resolution — watch the RGBA byte-format trap: `ui.Image.toByteData()` defaults to *premultiplied* `rawRgba`, there is no `rawStraightRgba` format in `dart:ui`, so on-device capture must round-trip through PNG (or explicitly un-premultiply) before the comparator) and the tier-3 evaluator that drives `applens_compare`'s `VisualComparator` and writes the verdict + diff PNG to the run store.

**Tier 4 — advisory (never gating).** Perceptual-hash tripwires on un-tagged nodes if enabled; VLM review only inside triage. No tier-4 result can fail a run.

---

## 9. Baseline lifecycle — the single-gate workflow

Baselines have three states: approved, proposed, rejected. The lifecycle is designed so the human gate never blocks testing:

1. Nightly run: node X's golden mismatches → failed_soft, evidence to run store.
2. Triage (AI, §12) classifies it *likely intended*, citing the correlated PR → writes a **proposal** (new golden + reasoning + PR link) to the store. The node YAML is untouched.
3. Every subsequent run compares against approved *and* open proposals: matches the proposal → `pending` (yellow, one quiet line), drifts beyond it → red again. Real regressions are never masked by an open proposal.
4. A human confirms in the report (which *is* the PR approval — one surface, one click). Triage clusters first: forty nodes sharing an app-bar change and one causal PR collapse to a single card and a single click.
5. On confirm, the sidecar applies the YAML mutation (new hash, provenance block, old hash retired but addressable), opens the PR, and the PR **auto-merges under a CI guard**: mergeable without review iff the diff touches only visual_baselines entries and golden files — never identity, edges, or assertions.
6. Unconfirmed proposals expire at the next release cut (configurable): shipping with unreviewed visual changes is the thing the expiry exists to prevent.

Hard rule preserved from first principles: AI proposes, applies, and merges guarded changes; only a human ever *decides*. Auto-approving "high-confidence intended" verdicts is permanently out of scope — one misjudged bug silently becomes the golden, and the pending state would hide the symptom while it waits. Triage accuracy is itself a tracked metric (human-overturn rate); above ~10%, fix the evidence package, not the policy.

---

## 10. SDK integration tiers — value at zero integration

Integration friction kills testing products, so capability is tiered:

**Tier 0 (dev_dependency only, ~15 minutes).** `applens init` adds applens_runner as a dev dependency and generates integration_test/applens_entry.dart (runner host + NavigatorObserver). Available immediately: full driver actions, tier 1 and 2 oracles, route-based identity, crawler, goldens with UI-inferred flags. No production code touched. Flags are inferred from observable widget state by a `UiInferenceFlagSource` of declared probes (e.g. `CountProbe('cart_count', 'cart_item_')`, `PresenceProbe`), composed into the fingerprint behind the runner's `FlagSource` seam.

**Tier 1 (applens_sdk in the app, opt-in).** Adds: `TestClock` (injectable clock — mandatory in practice for any app that renders time); a state registry, `AppLensState`, the app writes cheap state probes into (`AppLensState.setFlag('cart_count', 3)`, `journey.started`), which the runner reads via a `CallbackFlagSource(() => AppLensState.flags)` — precise flag-based identity and guard preconditions an inference can only approximate. (AppLens runs in the app's own isolate, so this is a direct in-process registry rather than the out-of-process `dart:developer` service extension cross-process tools would need; `applens_runner` never depends on `applens_sdk` — the entrypoint bridges them.) Plus seed hooks (`AppLensState.reset()` between paths). All of it is a no-op in release builds, so it compiles out of shipping apps. Guards (`requires: [journey.started]`) are evaluated against these flags at runtime, gated like any tier; a node reached with an unmet precondition is a finding.

**Tier 2 (conventions).** Widget-key naming conventions plus a lint package, so anchors and selectors stay stable by construction. Optional, recommended, enforced only by lint.

The stranger-app test is permanent: the examples/stranger_app integration must stay green using only Tier 0 + the README. The day it needs special access, the product has regressed into an internal tool.

---

## 11. Crawler — graph bootstrap

For a product, crawler-first onboarding is mandatory: a prospective user gives the tool thirty minutes, not three weeks of hand-authoring.

`applens crawl` explores the app breadth-first within a time/depth budget: at each state it enumerates actionable widgets, prioritizes never-tapped keys, performs the action, fingerprints the result, and clusters states by (route, tree shape) into *proposed* nodes with proposed edges. Text inputs use type-aware sample data; destructive-looking actions (delete, submit, pay) are flagged and skipped unless allowed. Output is a draft graph as a PR — never merged automatically; the human prunes, renames, and approves. With an API key configured, the sidecar improves the draft: VLM-suggested node names, anchor recommendations, and obvious assertion stubs.

The crawl is also rerunnable for *drift detection*: a periodic crawl diffed against the approved graph surfaces screens and actions that exist in the app but not in the model — coverage decay made visible.

---

## 12. AI sidecar — provider-agnostic by design

The sidecar is provider-blind. All sidecar logic (triage, authoring, healing, clustering) builds an `EvidencePackage` and expects a structured, schema-validated `Verdict` back — it never references any specific model or vendor. Provider swapping happens at one seam, the `LlmProvider` port (in package `applens_llm`), the same swappability principle as DriverInterface one level up:

```dart
abstract class LlmProvider {
  Future<LlmResult> complete(LlmRequest request);   // prompt + optional images → typed JSON
  LlmCapabilities get capabilities;                  // vision? json-mode? max context?
}
```

Output is always structured JSON validated against a declared schema (e.g. `{verdict, confidence, reasoning, causal_pr}`), never free text — this is what survives a provider swap. Each adapter uses its provider's native JSON/tool mode internally and normalizes to the AppLens type. The `capabilities()` method handles real provider differences: triage checks `capabilities.vision` (diff images need it) and degrades gracefully to text-only tree-diff rather than assuming. Adapters ship for Claude (Messages API, the default), OpenAI, Gemini, and local OpenAI-compatible endpoints (Ollama); the OSS includes at least two so provider-agnosticism is demonstrable, not just claimed.

**Two distinctions the abstraction deliberately enforces.** First, *model swap ≠ delivery swap*: any LLM behind `LlmProvider` swaps freely (easy axis); agentic coding harnesses (Kilo Code, Claude Code) are NOT providers — they are build-time tools for developing AppLens, and any future runtime agentic capability (e.g. multi-step fix drafting) gets its own larger interface, never this request/response port. Second, **ManualProvider is a first-class adapter and the Phase-1 mode**: it implements the same interface with a human as the transport — `complete()` writes the evidence package to disk, prompts the operator to paste it into Claude Desktop (or any chat UI), and blocks until the verdict file appears. This makes "use Desktop initially" a legitimate implementation of the production contract, not throwaway scaffolding: the day `ClaudeProvider` is wired in, nothing above the port changes, and every manual verdict collected becomes eval data for validating the automated providers.

**BYO-key local mode (ships with OSS).** `applens triage` runs single-run triage and authoring against the user's own provider key (env var / config). Credible OSS requires this — a "smart" tool whose intelligence is hostage to a SaaS would be rejected by the exact eng-lead audience targeted.

**Hosted cloud (the future business).** Adds what genuinely needs a service: cross-run failure history and flake fingerprinting, multi-node clustering, team review UI with the one-click confirm flow, org-level analytics. The free/paid line is "needs persistent multi-run state and a team surface," which is also the honest technical line. The hosted service implements the same provider contract behind its own key.

Sidecar capabilities, all emitting proposals/PRs and nothing else:

*Triage* — input is an evidence package: diff images, tree diffs, node metadata, and the commits touching the node's module since the last green run. Output: bug / intended / flake classification with cited reasoning. The repo correlation is the moat.

*Clustering* — groups failures by shared region, shared causal PR, shared selector; collapses N failures into one decision.

*Authoring* — natural-language test cases (or a spreadsheet of them) → draft node/edge/assertion YAML as a PR.

*Healing* — when an anchor or selector stops resolving, propose the renamed key by tree similarity, as a graph PR.

*Fix drafting (later)* — for triage-confirmed bugs, open a code-fix PR; lands behind the same human gate.

---

## 13. Run store, report, CI

The run store is SQLite — one file per CI run uploaded as an artifact, mergeable locally for history (the hosted service does longitudinal storage properly). Schema: runs, node_visits (outcome, durations, fingerprints), assertion_results, artifacts, proposals, triage_verdicts.

`applens report` renders a static, dependency-free HTML file: coverage (node %, edge %, trend if history present), failures pre-sorted by triage verdict, pending proposals with one-click confirm links (deep-linking to the VCS PR), blocked-node analysis with the broken edge highlighted, and flake suspects. Exit codes make CI policy trivial: 0 green, 1 red, 2 pending-only (team-configurable as pass or fail).

CI surface v1: a GitHub Action (`applens-run`) wrapping plan-compile + emulator boot + run + report upload + PR comment with the summary. The VCS adapter behind PR creation/approval/auto-merge-guard is an interface from day one (GitHub first; GitLab/ADO adapters are contributions the OSS structure should invite).

---

## 14. Technology choices and rationale

**Dependency policy (project law, governs every "do we fork X" debate).** Five rungs, escalate only when blocked, one rung at a time: (1) depend — use as published; (2) depend + own orchestration — their code unmodified, our wiring (the probable Patrol outcome); (3) contribute upstream — PR the decoupling we need (Patrol already split out patrol_finders; modularization PRs fit their direction, and upstreaming buys an OSS project credibility that forking destroys); (4) tracking fork — public, minimal patch set, rebased every upstream release: a carried diff, not a divorce; (5) clean rebuild — only when the needed component is genuinely small for our scope. Hard forks — copy once, diverge forever — appear nowhere on the ladder: they trade a bounded coupling problem for an unbounded maintenance problem and inherit someone else's platform churn with none of their team. Corollary already applied twice: own what sits on stable SDK surface (action engine, pixel comparator — the latter a rung-5 case, ported with attribution from a 150-line ISC algorithm); rent what tracks OS churn (native automation bridges).

Everything user-facing is Dart: core, runner, CLI, crawler, report generator. One language, the contributors' language, distributed on pub.dev, no Python/Node runtime demanded of users. The report is static HTML/JS with zero server. The sidecar service is implementation-free in this spec (its contract is the spec); the BYO-key local mode ships as a Dart package calling provider APIs directly. The pixel comparator is **ported, not depended on**: a first-party Dart translation of pixelmatch (ISC, with attribution), validated against the upstream test fixtures — the comparator is the heart of tier 3 and never sits behind someone else's release cycle. `package:image` is used only for PNG encode/decode; Flutter's golden machinery supplies capture, baseline plumbing, and the public `GoldenFileComparator` slot that applens_compare implements (Flutter's default comparator is exact-match, the #1 golden-test complaint — applens_compare replaces it in two lines for any team, AppLens user or not).

Two deliberate non-goals for v1: iOS-vs-Android visual parity testing (one profile per baseline context is the model; parity is a context-matrix feature later), and any web dashboard (the HTML report and the VCS are the entire surface until the hosted tier exists).

---

## 15. Honest market position

Against component golden tests: AppLens adds flows, coverage, and an app model; goldens become AppLens's tier 3 rather than a competitor. Against Maestro: Maestro has beautiful ergonomics and zero app model — no coverage semantics, no tree oracle, no impact analysis; AppLens plans are deliberately Maestro-readable while being compiled from a model. Against Appium-era tools: not Flutter-native, selector-fragile, no graph. Against AI-VLM testing startups: they are black-box and probabilistic at the *oracle*; AppLens is deterministic at the oracle and spends AI where it compounds (triage, authoring, healing) — and it is open source, which they structurally cannot be. Against cloud visual platforms (Percy/Applitools): web-first, no widget tree, no repo context; AppLens's review workflow borrows their best idea (approve-in-PR) without the per-screenshot pricing.

The defensible asset is not any single component — it is the graph schema as a de-facto standard, the corpus of conventions around it, and the repo-context triage loop.

---

## 16. Build order

Phase 0 — *the README*. Written before code: name, public API, init-to-first-green-run walkthrough. The README is the product spec; writing it surfaces every remaining gap.

Phase 1 — *walking skeleton on a stranger's app* (the permanent definition of done): hand-written 5-node graph, first-party action engine on integration_test (zero non-SDK dependencies; permissions pre-granted from applens.yaml; one scroll-into-long-list node included by design), tier-1 assertions only, determinism kit minus SDK, plan→run→HTML report, green in GitHub Actions two nights running, using only the README. No AI, no crawler, no goldens.

Phase 2 — *oracle depth*: tier 2 hashes, tier 3 scoped pixel comparison (pixelmatch port with fixture tests first, then comparator, capture, masks), baseline recording flow, validate command with fingerprint-ambiguity analysis. applens_compare ships publicly at the end of this phase as a standalone package — the first thing the community can adopt, months before the full graph product.

Phase 3 — *the loop*: run store, report polish, proposed/pending baseline states, GitHub adapter with the auto-merge guard, BYO-key triage with repo correlation.

Phase 4 — *onboarding at product grade*: crawler, AI authoring, impact strategy, clustering.

Phase 5 — *dogfood at scale*: FieldAssist's GT app as customer #1 through the public interface only; its pain becomes the roadmap. Hosted sidecar work begins only after external OSS users exist.

---

## 17. Open questions (decide before Phase 1 ends)

pub.dev namespace verification for the applens_* prefix (name decided: AppLens). License confirmation (Apache-2.0 vs MIT — Apache's patent grant favored). The IP shape (personal vs employer-sponsored) — decided before the first public commit, full stop. Selector grammar: keys-only at v1, or text/semantics fallbacks from the start (lean: keys + semantics, no text). Whether plan files are committed or always ephemeral. Minimum supported Flutter version policy.
