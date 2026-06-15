import 'package:applens_core/applens_core.dart';

import 'fingerprint.dart';

/// OracleTier order for the tier-1 (widget-tree) checks.
const int tier1Order = 10;

/// OracleTier order for guard (precondition) checks — the cheapest, evaluated
/// first so an unmet precondition short-circuits the deeper oracles.
const int guardOrder = 5;

/// Whether a guard `requires` token is satisfied by an observed flag [value]:
/// present and truthy. Falsey = absent, empty, `false` (any case), or a numeric
/// zero (`0`, `0.0`, `-0`) — so a guard isn't silently satisfied by a `'False'`
/// or `'0.0'` spelling. A non-zero number (including negative) and any other
/// non-empty literal are truthy.
bool _truthy(String? value) {
  if (value == null || value.isEmpty || value.toLowerCase() == 'false') {
    return false;
  }
  final number = num.tryParse(value);
  return number == null || number != 0;
}

/// Evaluates a node's guard preconditions against the observed [fingerprint]
/// flags (ARCHITECTURE.md §4): each `requires` token must name a flag that is
/// present and truthy. Returns null when the node declares no guard, so a node
/// without preconditions adds nothing. Reaching a node with an unmet guard is a
/// real finding (the app let you somewhere its precondition forbids) — gated
/// like any assertion, deterministic, no AI.
AssertionResult? evaluateGuard(Node node, Fingerprint fingerprint) {
  final guard = node.payload.guard;
  if (guard == null || guard.requires.isEmpty) {
    return null;
  }
  final unmet = [
    for (final token in guard.requires)
      if (!_truthy(fingerprint.flags[token])) token,
  ];
  return AssertionResult(
    tierOrder: guardOrder,
    type: 'guard_satisfied',
    passed: unmet.isEmpty,
    detail: unmet.isEmpty ? '' : 'unmet precondition(s): ${unmet.join(', ')}',
  );
}

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
      case 'text_equals':
        final key = assertion.args['key'];
        final expected = assertion.args['value'];
        if (key is! String || expected is! String) {
          results.add(AssertionResult(
            tierOrder: tier1Order,
            type: assertion.type,
            passed: false,
            detail: 'text_equals requires string "key" and "value" args',
          ));
          break;
        }
        if (!fingerprint.anchors.contains(key)) {
          results.add(AssertionResult(
            tierOrder: tier1Order,
            type: assertion.type,
            passed: false,
            detail: 'key "$key" not present',
          ));
          break;
        }
        final actual = fingerprint.texts[key];
        final match = actual == expected;
        results.add(AssertionResult(
          tierOrder: tier1Order,
          type: assertion.type,
          passed: match,
          detail: match
              ? ''
              : 'expected "$expected" but got "${actual ?? '<no text>'}"',
        ));
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
