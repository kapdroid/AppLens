import 'dart:typed_data';
import 'dart:ui';

import 'package:applens_compare/applens_compare.dart';
import 'package:applens_core/applens_core.dart';

import '../driver/driver.dart';

/// OracleTier order for the tier-2.5 (semantic: text + geometry) checks —
/// between the layout-hash tier (20) and the visual tier (30).
const int semanticOrder = 25;

/// The default per-edge geometry tolerance, in normalized units (fraction of the
/// screen). A widget must move/resize by more than this to count as drifted —
/// absorbing antialiasing and sub-pixel rounding, like the tier-3 threshold.
const double defaultGeometryTolerance = 0.02;

/// What a semantic diff found at one widget (ARCHITECTURE.md §8 tier 2.5). Each
/// finding carries the normalized [bounds] to highlight and a human [describe].
enum FindingKind { textChanged, moved, removed, added }

class StructuralFinding {
  const StructuralFinding({
    required this.kind,
    required this.type,
    required this.bounds,
    this.key,
    this.oldText,
    this.newText,
    this.oldBounds,
  });

  final FindingKind kind;
  final String type;

  /// The region to highlight: the current bounds for a change/add, the baseline
  /// bounds for a removal.
  final NormalizedRect bounds;

  final String? key;
  final String? oldText;
  final String? newText;
  final NormalizedRect? oldBounds;

  /// A short caption for the highlight box and the report.
  String describe() {
    final who = key ?? type;
    switch (kind) {
      case FindingKind.textChanged:
        return '$who: "${oldText ?? ''}" → "${newText ?? ''}"';
      case FindingKind.moved:
        return '$who: moved';
      case FindingKind.removed:
        return '$who: removed';
      case FindingKind.added:
        return '$who: added';
    }
  }

  @override
  String toString() => describe();
}

/// Captures the node's semantic snapshot from the live widget [tree]: the
/// identifiable widgets (keyed, plus unkeyed Text outside any keyed widget) with
/// their text and bounds normalized to the root (0..1). A keyed widget carries
/// its first Text descendant as [WidgetSnapshot.text] — the same text the
/// fingerprint exposes — so it is tracked by key and its label together. Pure
/// given the tree; no AI (CLAUDE.md).
StructuralSnapshot captureStructural(WidgetTreeSnapshot tree) {
  final widgets = <WidgetSnapshot>[];

  // The normalization frame is the largest-area box in the tree — the
  // screen-filling container. The tree's actual root is a RenderView (not a
  // RenderBox, so it has no rect), and the largest box is stable when a single
  // widget's text or position changes, unlike a content bounding-box union. An
  // area tie is broken by origin (topmost, then leftmost) so the frame is
  // independent of traversal order — two same-area boxes must not let a layout
  // reorder shift every widget's normalization (a determinism hole).
  Rect? frame;
  bool betterFrame(Rect r, Rect cur) {
    final ra = r.width * r.height;
    final ca = cur.width * cur.height;
    if (ra != ca) return ra > ca;
    if (r.top != cur.top) return r.top < cur.top;
    return r.left < cur.left;
  }

  void findFrame(SerializedWidget n) {
    final r = n.rect;
    if (r != null && (frame == null || betterFrame(r, frame!))) {
      frame = r;
    }
    for (final c in n.children) {
      findFrame(c);
    }
  }

  findFrame(tree.root);
  final root = frame;
  if (root == null || root.width <= 0 || root.height <= 0) {
    return StructuralSnapshot(widgets);
  }

  NormalizedRect norm(Rect r) => NormalizedRect(
        (r.left - root.left) / root.width,
        (r.top - root.top) / root.height,
        r.width / root.width,
        r.height / root.height,
      );

  // A keyed widget records *all* its Text descendants joined, not just the
  // first — otherwise a change in a second text inside a keyed container (e.g. a
  // price under a title) is silently lost, since the inner Text is suppressed as
  // a separate entry. Returns null when the subtree has no text.
  String? subtreeText(SerializedWidget n) {
    final parts = <String>[];
    void walk(SerializedWidget w) {
      if (w.text != null) {
        // Take this visible string and stop: its render subtree (e.g. the
        // RichText a Text builds) repeats it, which would double-count.
        parts.add(w.text!);
        return;
      }
      for (final c in w.children) {
        walk(c);
      }
    }

    walk(n);
    return parts.isEmpty ? null : parts.join(' ');
  }

  // A keyed widget or a Text is usually a composite whose own element carries no
  // RenderBox — its painted bounds live on a descendant (e.g. a RenderParagraph).
  // The widget's bounds are therefore the union of its subtree's rects.
  Rect? subtreeBounds(SerializedWidget n) {
    var acc = n.rect;
    for (final c in n.children) {
      final cb = subtreeBounds(c);
      if (cb != null) acc = acc == null ? cb : acc.expandToInclude(cb);
    }
    return acc;
  }

  void visit(SerializedWidget node, bool insideKeyed) {
    if (node.key != null) {
      final bounds = subtreeBounds(node);
      if (bounds != null) {
        widgets.add(WidgetSnapshot(
          type: node.type,
          key: node.key,
          text: subtreeText(node),
          bounds: norm(bounds),
        ));
      }
      // A keyed widget owns its subtree's text/geometry; descend only to surface
      // any *nested keyed* widget, suppressing duplicate unkeyed-text entries.
      for (final c in node.children) {
        visit(c, true);
      }
    } else if (node.text != null && !insideKeyed) {
      final bounds = subtreeBounds(node);
      if (bounds != null) {
        widgets.add(WidgetSnapshot(
          type: node.type,
          text: node.text,
          bounds: norm(bounds),
        ));
      }
      // This Text's render subtree (e.g. its RichText) repeats the same string;
      // suppress so one visible string is one snapshot entry.
      for (final c in node.children) {
        visit(c, true);
      }
    } else {
      for (final c in node.children) {
        visit(c, insideKeyed);
      }
    }
  }

  visit(tree.root, false);
  return StructuralSnapshot(widgets);
}

/// The result of pairing two snapshots' widgets: matched [pairs] plus the
/// widgets present only in the baseline ([removed]) or only now ([added]).
class WidgetMatch {
  const WidgetMatch({
    required this.pairs,
    required this.removed,
    required this.added,
  });

  final List<(WidgetSnapshot baseline, WidgetSnapshot current)> pairs;
  final List<WidgetSnapshot> removed;
  final List<WidgetSnapshot> added;
}

/// Pairs baseline ↔ current widgets by the strongest available identity
/// (ARCHITECTURE.md §8): first by [WidgetSnapshot.key] (when it appears exactly
/// once on each side), then by a unique `(type, text)` for the still-unmatched.
/// Whatever stays unmatched is reported as removed/added rather than forced into
/// a fragile positional pairing. Deterministic.
WidgetMatch matchWidgets(
  List<WidgetSnapshot> baseline,
  List<WidgetSnapshot> current,
) {
  final pairs = <(WidgetSnapshot, WidgetSnapshot)>[];
  final baseLeft = List<WidgetSnapshot?>.of(baseline);
  final currLeft = List<WidgetSnapshot?>.of(current);

  // Rung 1: by key, only when the key is unambiguous (exactly one each side).
  int? soleIndexWithKey(List<WidgetSnapshot?> list, String key) {
    int? found;
    for (var i = 0; i < list.length; i++) {
      if (list[i]?.key == key) {
        if (found != null) return null; // ambiguous
        found = i;
      }
    }
    return found;
  }

  for (var i = 0; i < baseLeft.length; i++) {
    final b = baseLeft[i];
    final key = b?.key;
    if (b == null || key == null) continue;
    if (soleIndexWithKey(baseLeft, key) != i) continue; // ambiguous on baseline
    final j = soleIndexWithKey(currLeft, key);
    if (j == null) continue;
    pairs.add((b, currLeft[j]!));
    baseLeft[i] = null;
    currLeft[j] = null;
  }

  // Rung 2: by unique (type, text) among the still-unmatched *unkeyed* widgets
  // only (text must be present). A widget that carries a key is identified by
  // its key alone — if rung 1 left it unmatched (its key is absent or ambiguous
  // on the other side) it is genuinely removed/added, and must NOT be rescued by
  // a text match to a *differently*-keyed widget.
  int? soleUnkeyedWithSig(
      List<WidgetSnapshot?> list, String type, String text) {
    int? found;
    for (var i = 0; i < list.length; i++) {
      final w = list[i];
      if (w != null && w.key == null && w.type == type && w.text == text) {
        if (found != null) return null;
        found = i;
      }
    }
    return found;
  }

  for (var i = 0; i < baseLeft.length; i++) {
    final b = baseLeft[i];
    final text = b?.text;
    if (b == null || b.key != null || text == null) continue;
    if (soleUnkeyedWithSig(baseLeft, b.type, text) != i) continue;
    final j = soleUnkeyedWithSig(currLeft, b.type, text);
    if (j == null) continue;
    pairs.add((b, currLeft[j]!));
    baseLeft[i] = null;
    currLeft[j] = null;
  }

  return WidgetMatch(
    pairs: pairs,
    removed: [
      for (final b in baseLeft)
        if (b != null) b
    ],
    added: [
      for (final c in currLeft)
        if (c != null) c
    ],
  );
}

/// Diffs a [match] into findings, scoped by [watch] (ARCHITECTURE.md §8). A
/// matched pair yields a `textChanged` finding when its text differs and a
/// `moved` finding when its bounds drift beyond [tolerance]; a watched widget
/// that disappeared yields `removed`. Unwatched widgets are skipped. Pure.
List<StructuralFinding> diffStructural(
  WidgetMatch match, {
  WatchSpec watch = const WatchSpec(),
  double tolerance = defaultGeometryTolerance,
}) {
  final findings = <StructuralFinding>[];
  for (final (b, c) in match.pairs) {
    if (!watch.watches(c.key)) continue;
    if (watch.text && b.text != c.text) {
      findings.add(StructuralFinding(
        kind: FindingKind.textChanged,
        type: c.type,
        key: c.key,
        oldText: b.text,
        newText: c.text,
        bounds: c.bounds,
      ));
    }
    if (watch.layout && b.bounds.differsFrom(c.bounds, tolerance)) {
      findings.add(StructuralFinding(
        kind: FindingKind.moved,
        type: c.type,
        key: c.key,
        oldBounds: b.bounds,
        bounds: c.bounds,
      ));
    }
  }
  // A watched widget that vanished is a regression; only report it when the
  // author named it explicitly (watch.keys), so auto-tracking stays low-noise.
  for (final b in match.removed) {
    if (watch.keys.isNotEmpty && b.key != null && watch.keys.contains(b.key)) {
      findings.add(StructuralFinding(
        kind: FindingKind.removed,
        type: b.type,
        key: b.key,
        oldText: b.text,
        bounds: b.bounds,
      ));
    }
  }
  return findings;
}

/// Draws [findings] as labeled highlight boxes over [capture] (ARCHITECTURE.md
/// §8) — the localized failure overlay for the report. Converts each finding's
/// normalized bounds into pixel coordinates against the capture's resolution,
/// then defers the drawing to the standalone compare annotator.
Uint8List annotateFindings(Capture capture, List<StructuralFinding> findings) {
  AnnotationStyle styleOf(FindingKind kind) => switch (kind) {
        FindingKind.textChanged => AnnotationStyle.changed,
        FindingKind.moved => AnnotationStyle.moved,
        FindingKind.removed => AnnotationStyle.removed,
        FindingKind.added => AnnotationStyle.changed,
      };
  final boxes = [
    for (final f in findings)
      AnnotationBox(
        x: (f.bounds.left * capture.width).round(),
        y: (f.bounds.top * capture.height).round(),
        width: (f.bounds.width * capture.width).round(),
        height: (f.bounds.height * capture.height).round(),
        label: f.describe(),
        style: styleOf(f.kind),
      ),
  ];
  return annotate(capture.pngBytes, boxes);
}

/// Folds [findings] into the tier-2.5 assertion result: passed when empty, a
/// `failedSoft`-worthy fail listing each change otherwise. The semantic tier
/// gates deterministically like every other tier (CLAUDE.md — AI never gates).
AssertionResult semanticResult(List<StructuralFinding> findings) =>
    findings.isEmpty
        ? const AssertionResult(
            tierOrder: semanticOrder, type: 'semantic_match', passed: true)
        : AssertionResult(
            tierOrder: semanticOrder,
            type: 'semantic_match',
            passed: false,
            detail: findings.map((f) => f.describe()).join('; '),
          );
