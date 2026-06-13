import 'package:applens_core/applens_core.dart';

import 'fingerprint.dart';

/// OracleTier order for the tier-1 (widget-tree) checks.
const int tier1Order = 10;

/// Evaluates a node's tier-1 assertions against an observed [fingerprint].
///
/// v1 evaluates key-existence assertions (`widget_exists` / `widget_absent`)
/// against the anchor probe. Richer tier-1 checks (`text_equals`, list counts,
/// enabled state, semantics) need a snapshot that carries those values and land
/// later; they are recorded as `skipped`, never as silent passes.
List<AssertionResult> evaluateTier1(Node node, Fingerprint fingerprint) {
  final results = <AssertionResult>[];
  for (final assertion in node.payload.assertions) {
    switch (assertion.type) {
      case 'widget_exists':
        final key = assertion.args['key'];
        final present = key is String && fingerprint.anchors.contains(key);
        results.add(
          AssertionResult(
            tierOrder: tier1Order,
            type: assertion.type,
            passed: present,
            detail: present ? '' : 'key "$key" not present',
          ),
        );
      case 'widget_absent':
        final key = assertion.args['key'];
        final absent = key is String && !fingerprint.anchors.contains(key);
        results.add(
          AssertionResult(
            tierOrder: tier1Order,
            type: assertion.type,
            passed: absent,
            detail: absent ? '' : 'key "$key" unexpectedly present',
          ),
        );
      default:
        results.add(
          AssertionResult(
            tierOrder: tier1Order,
            type: assertion.type,
            passed: true,
            skipped: true,
            detail: 'not evaluable from the tier-1 fingerprint yet',
          ),
        );
    }
  }
  return results;
}
