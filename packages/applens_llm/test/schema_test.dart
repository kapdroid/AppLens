import 'package:applens_llm/applens_llm.dart';
import 'package:test/test.dart';

/// The canonical triage verdict schema (ARCHITECTURE.md §12).
const _verdictSchema = <String, Object?>{
  'type': 'object',
  'required': ['verdict', 'confidence', 'reasoning'],
  'properties': {
    'verdict': {
      'type': 'string',
      'enum': ['bug', 'intended', 'flake'],
    },
    'confidence': {'type': 'number'},
    'reasoning': {'type': 'string'},
    'causal_pr': {'type': 'string', 'nullable': true},
  },
};

void main() {
  test('a well-formed verdict validates', () {
    expect(
      validateAgainstSchema({
        'verdict': 'intended',
        'confidence': 0.9,
        'reasoning': 'matches the restyle PR',
        'causal_pr': 'https://github.com/o/r/pull/7',
      }, _verdictSchema),
      isEmpty,
    );
  });

  test('a null nullable field is allowed', () {
    expect(
      validateAgainstSchema({
        'verdict': 'flake',
        'confidence': 0.3,
        'reasoning': 'nondeterministic',
        'causal_pr': null,
      }, _verdictSchema),
      isEmpty,
    );
  });

  test('a missing required field is reported with its path', () {
    final errors = validateAgainstSchema(
      {'verdict': 'bug', 'confidence': 0.8},
      _verdictSchema,
    );
    expect(errors, isNotEmpty);
    expect(errors.join(), contains('reasoning'));
  });

  test('an out-of-enum value is rejected', () {
    final errors = validateAgainstSchema({
      'verdict': 'maybe',
      'confidence': 0.5,
      'reasoning': 'x',
    }, _verdictSchema);
    expect(errors.join(), contains('verdict'));
  });

  test('a wrong type is rejected', () {
    final errors = validateAgainstSchema({
      'verdict': 'bug',
      'confidence': 'high', // should be a number
      'reasoning': 'x',
    }, _verdictSchema);
    expect(errors.join(), contains('confidence'));
  });
}
