import 'dart:typed_data';

import 'package:applens_compare/applens_compare.dart';
import 'package:applens_core/applens_core.dart';

import '../driver/driver.dart';

/// OracleTier order for the tier-3 (scoped pixel / golden) checks.
const int tier3Order = 30;

/// The outcome of a tier-3 comparison: the assertion result plus the red diff
/// overlay (present only on a mismatch) for the run store.
class VisualTierResult {
  const VisualTierResult({required this.assertion, this.diffPng});

  final AssertionResult assertion;
  final Uint8List? diffPng;
}

/// Compares a freshly captured screen against its approved baseline using the
/// standalone [VisualComparator] (ARCHITECTURE.md §8). Both [actual] and the
/// baseline are PNG bytes, so they feed the comparator's PNG-in contract
/// directly. Masks and per-node thresholds are baked into [comparator] by the
/// caller (resolved from the node's [VisualBaseline]).
///
/// A node with no approved baseline yields a *skipped* result — never a silent
/// pass or fail; recording that baseline is the proposal workflow's job (§9).
/// Pure given its inputs: no AI, no nondeterminism (CLAUDE.md).
VisualTierResult evaluateTier3({
  required Capture actual,
  required Uint8List? baselinePng,
  VisualComparator comparator = const VisualComparator(),
}) {
  if (baselinePng == null) {
    return const VisualTierResult(
      assertion: AssertionResult(
        tierOrder: tier3Order,
        type: 'visual_match',
        passed: true,
        skipped: true,
        detail: 'no approved baseline recorded for this node',
      ),
    );
  }

  final verdict = comparator.compare(actual.pngBytes, baselinePng);
  return VisualTierResult(
    assertion: AssertionResult(
      tierOrder: tier3Order,
      type: 'visual_match',
      passed: verdict.matches,
      detail: verdict.matches
          ? ''
          : '${verdict.mismatchedPixels}px differ '
              '(${(verdict.diffRatio * 100).toStringAsFixed(3)}%)',
    ),
    diffPng: verdict.diffPng,
  );
}
