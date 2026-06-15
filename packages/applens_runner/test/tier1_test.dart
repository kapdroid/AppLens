import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/src/run/fingerprint.dart';
import 'package:applens_runner/src/run/tier1.dart';
import 'package:flutter_test/flutter_test.dart';

Node _node(List<Map<String, dynamic>> assertions) => parseNode('''
identity:
  route: /test
  anchors: [btn]
payload:
  assertions:
${assertions.map((a) {
      final args = a.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      return '    - { $args }';
    }).join('\n')}
''', source: 'test', assignedId: 'test');

Fingerprint _fp(
        {Set<String> anchors = const {},
        Map<String, String> texts = const {},
        Map<String, String> flags = const {}}) =>
    Fingerprint(anchors: anchors, texts: texts, flags: flags);

Node _guarded(List<String> requires) => parseNode('''
identity:
  route: /test
payload:
  guards: { requires: [${requires.join(', ')}] }
''', source: 'test', assignedId: 'test');

void main() {
  group('text_equals', () {
    test('passes when text matches', () {
      final node = _node([
        {'type': 'text_equals', 'key': 'btn', 'value': '"Start shopping"'},
      ]);
      final fp = _fp(anchors: {'btn'}, texts: {'btn': 'Start shopping'});
      final results = evaluateTier1(node, fp);
      expect(results, hasLength(1));
      expect(results.first.passed, isTrue);
      expect(results.first.skipped, isFalse);
    });

    test('fails when text differs', () {
      final node = _node([
        {'type': 'text_equals', 'key': 'btn', 'value': '"Start shopping"'},
      ]);
      final fp = _fp(anchors: {'btn'}, texts: {'btn': 'Start'});
      final results = evaluateTier1(node, fp);
      expect(results.first.passed, isFalse);
      expect(results.first.detail, contains('Start shopping'));
      expect(results.first.detail, contains('Start'));
    });

    test('fails when the key is absent from the tree', () {
      final node = _node([
        {'type': 'text_equals', 'key': 'btn', 'value': '"Start shopping"'},
      ]);
      final fp = _fp(anchors: {}); // btn not present
      final results = evaluateTier1(node, fp);
      expect(results.first.passed, isFalse);
      expect(results.first.detail, contains('"btn" not present'));
    });

    test('fails when the key is present but has no text child', () {
      final node = _node([
        {'type': 'text_equals', 'key': 'btn', 'value': '"Start shopping"'},
      ]);
      final fp = _fp(anchors: {'btn'}, texts: {}); // no text found
      final results = evaluateTier1(node, fp);
      expect(results.first.passed, isFalse);
      expect(results.first.detail, contains('<no text>'));
    });
  });

  group('widget_exists still works alongside text_equals', () {
    test('both pass', () {
      final node = _node([
        {'type': 'widget_exists', 'key': 'btn'},
        {'type': 'text_equals', 'key': 'btn', 'value': '"Go"'},
      ]);
      final fp = _fp(anchors: {'btn'}, texts: {'btn': 'Go'});
      final results = evaluateTier1(node, fp);
      expect(results, hasLength(2));
      expect(results.every((r) => r.passed), isTrue);
    });
  });

  group('evaluateGuard', () {
    test('a node without a guard yields no result', () {
      final node = _node([
        {'type': 'widget_exists', 'key': 'btn'}
      ]);
      expect(evaluateGuard(node, _fp()), isNull);
    });

    test('passes when every required flag is truthy', () {
      final node = _guarded(['journey.started']);
      final r = evaluateGuard(node, _fp(flags: {'journey.started': 'true'}));
      expect(r!.type, 'guard_satisfied');
      expect(r.passed, isTrue);
    });

    test('fails and names the unmet precondition when a flag is absent', () {
      final node = _guarded(['journey.started']);
      final r = evaluateGuard(node, _fp())!;
      expect(r.passed, isFalse);
      expect(r.detail, contains('journey.started'));
    });

    test('false / 0 / empty are not truthy', () {
      final node = _guarded(['a', 'b', 'c']);
      final r =
          evaluateGuard(node, _fp(flags: {'a': 'false', 'b': '0', 'c': ''}))!;
      expect(r.passed, isFalse);
      expect(r.detail, allOf(contains('a'), contains('b'), contains('c')));
    });

    test('falsey spellings (False, 0.0) are not truthy; -1 is', () {
      final node = _guarded(['cap', 'zero', 'neg']);
      final r = evaluateGuard(
          node, _fp(flags: {'cap': 'False', 'zero': '0.0', 'neg': '-1'}))!;
      expect(r.passed, isFalse); // cap + zero are unmet
      expect(r.detail, allOf(contains('cap'), contains('zero')));
      expect(r.detail, isNot(contains('neg'))); // -1 is non-zero → truthy
    });

    test('a positive integer flag satisfies a require token', () {
      final node = _guarded(['cart_count']);
      expect(
          evaluateGuard(node, _fp(flags: {'cart_count': '3'}))!.passed, isTrue);
    });
  });
}
