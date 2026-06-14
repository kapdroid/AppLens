import 'dart:convert';

import 'package:applens_core/applens_core.dart';
import 'package:crypto/crypto.dart';

import '../driver/driver.dart';

/// OracleTier order for the tier-2 (layout-hash) checks.
const int tier2Order = 20;

/// A normalized, data-stripped hash of the widget tree's *shape* — widget
/// types, depths, child order, and relative geometry buckets (ARCHITECTURE.md
/// §8 tier 2). Insensitive to data values and sub-bucket pixel jitter, sensitive
/// to structural change. Keys are deliberately excluded: which node this is is
/// tier 1's job, so the same layout under different keys hashes identically.
///
/// Geometry is bucketed relative to the root's bounds into [buckets] divisions
/// per axis, so the hash survives small rendering shifts but flags a widget that
/// jumps across a bucket boundary. When a node carries no geometry (e.g. a
/// scripted or sliver-only tree) the hash degrades cleanly to type/depth/order.
/// Like a golden, a hash is only comparable within the environment it was
/// captured in.
String layoutHash(WidgetTreeSnapshot tree, {int buckets = 12}) {
  final shape = StringBuffer();
  final rootRect = tree.root.rect;

  // Negative relative offsets (off-root/transformed children) get their own
  // buckets rather than all collapsing to 0, so a move within that band still
  // changes the hash; the top edge still clamps to the last bucket.
  int bucketOf(double value, double extent) =>
      ((value / extent) * buckets).floor().clamp(-buckets, buckets - 1);

  void visit(SerializedWidget widget, int depth) {
    shape
      ..write(widget.type)
      ..write('@')
      ..write(depth);
    final rect = widget.rect;
    if (rootRect != null &&
        rect != null &&
        rootRect.width > 0 &&
        rootRect.height > 0) {
      shape
        ..write('[')
        ..write(bucketOf(rect.left - rootRect.left, rootRect.width))
        ..write(',')
        ..write(bucketOf(rect.top - rootRect.top, rootRect.height))
        ..write(',')
        ..write(bucketOf(rect.width, rootRect.width))
        ..write(',')
        ..write(bucketOf(rect.height, rootRect.height))
        ..write(']');
    }
    shape.write('{');
    for (final child in widget.children) {
      visit(child, depth + 1);
    }
    shape.write('}');
  }

  visit(tree.root, 0);
  final digest = sha256.convert(utf8.encode(shape.toString()));
  return 'sha256:${digest.toString().substring(0, 32)}';
}

/// Evaluates a node's tier-2 `layout_hash` assertions against the observed
/// [tree]. A node without a `layout_hash` assertion produces no tier-2 results
/// (it simply opts out of the tier). Pure given its inputs — no nondeterminism,
/// no AI (CLAUDE.md).
List<AssertionResult> evaluateTier2(Node node, WidgetTreeSnapshot tree) {
  final results = <AssertionResult>[];
  for (final assertion in node.payload.assertions) {
    if (assertion.type != 'layout_hash') {
      continue;
    }
    // The baseline hash is keyed `baseline` (ARCHITECTURE.md §4; the validator
    // warns when it's absent). Reading any other key would silently always-fail.
    final expected = assertion.args['baseline'];
    final observed = layoutHash(tree);
    final passed = expected == observed;
    results.add(
      AssertionResult(
        tierOrder: tier2Order,
        type: 'layout_hash',
        passed: passed,
        detail: passed ? '' : 'layout hash $observed != baseline $expected',
      ),
    );
  }
  return results;
}
