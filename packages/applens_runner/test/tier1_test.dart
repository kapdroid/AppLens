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
        Map<String, String> texts = const {}}) =>
    Fingerprint(anchors: anchors, texts: texts);

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
}
