import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/src/driver/driver.dart';
import 'package:applens_runner/src/run/tier2.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A root spanning 1200×1200 so each of the 12 default buckets is exactly
/// 100 logical px — makes the bucket arithmetic in the tests obvious.
WidgetTreeSnapshot _tree(List<SerializedWidget> children) => WidgetTreeSnapshot(
      SerializedWidget(
        type: 'Root',
        rect: const Rect.fromLTWH(0, 0, 1200, 1200),
        children: children,
      ),
    );

SerializedWidget _w(
  String type, {
  String? key,
  Rect rect = const Rect.fromLTWH(0, 0, 100, 40),
  List<SerializedWidget> children = const [],
}) =>
    SerializedWidget(type: type, key: key, rect: rect, children: children);

void main() {
  group('layoutHash', () {
    test('is deterministic and content-addressed', () {
      expect(layoutHash(_tree([_w('Text')])), startsWith('sha256:'));
      expect(layoutHash(_tree([_w('Text')])), layoutHash(_tree([_w('Text')])));
    });

    test('ignores keys — it hashes shape, not identity (tier 1 owns identity)',
        () {
      final base = layoutHash(_tree([_w('Text')]));
      expect(layoutHash(_tree([_w('Text', key: 'a')])), base);
      expect(
          layoutHash(_tree([_w('Text', key: 'completely-different')])), base);
    });

    test('changes when a widget type changes', () {
      expect(
        layoutHash(_tree([_w('Text')])),
        isNot(layoutHash(_tree([_w('Icon')]))),
      );
    });

    test('changes when structure changes (an extra child appears)', () {
      expect(
        layoutHash(_tree([_w('Text')])),
        isNot(layoutHash(_tree([
          _w('Text'),
          _w('Text', rect: const Rect.fromLTWH(0, 50, 100, 40)),
        ]))),
      );
    });

    test('changes when children are reordered', () {
      expect(
        layoutHash(_tree([_w('A'), _w('B')])),
        isNot(layoutHash(_tree([_w('B'), _w('A')]))),
      );
    });

    test('tolerates sub-bucket jitter but flags a cross-bucket move', () {
      // 100px buckets: 10→40 stays in bucket 0; 10→150 crosses into bucket 1.
      final base = layoutHash(_tree([_w('Card', rect: rectAt(10, 10))]));
      expect(layoutHash(_tree([_w('Card', rect: rectAt(40, 40))])), base);
      expect(
        layoutHash(_tree([_w('Card', rect: rectAt(150, 10))])),
        isNot(base),
      );
    });

    test('handles a mixed tree — root has geometry, a child does not', () {
      // The real production shape: a box-backed root over a sliver/non-box
      // child whose rect is null. Must stay deterministic and structure-aware.
      WidgetTreeSnapshot mixed(String childType) => WidgetTreeSnapshot(
            SerializedWidget(
              type: 'Root',
              rect: const Rect.fromLTWH(0, 0, 1200, 1200),
              children: [
                const SerializedWidget(type: 'Sliver'), // null rect
                _w(childType),
              ],
            ),
          );
      expect(layoutHash(mixed('Text')), layoutHash(mixed('Text')));
      expect(layoutHash(mixed('Text')), isNot(layoutHash(mixed('Icon'))));
    });

    test('falls back to type/depth shape when geometry is absent', () {
      // No rects anywhere → still deterministic and structure-sensitive.
      const a = WidgetTreeSnapshot(SerializedWidget(type: 'Root', children: [
        SerializedWidget(type: 'Text'),
      ]));
      const b = WidgetTreeSnapshot(SerializedWidget(type: 'Root', children: [
        SerializedWidget(type: 'Text'),
        SerializedWidget(type: 'Icon'),
      ]));
      expect(layoutHash(a), layoutHash(a));
      expect(layoutHash(a), isNot(layoutHash(b)));
    });
  });

  group('evaluateTier2', () {
    Node node(List<Assertion> assertions) => Node(
          id: 'n',
          identity: const NodeIdentity(),
          payload: NodePayload(assertions: assertions),
        );

    test('passes when the observed hash matches the baseline', () {
      final tree = _tree([_w('Text')]);
      final baseline = layoutHash(tree);
      final results = evaluateTier2(
        node([
          Assertion(type: 'layout_hash', args: {'value': baseline})
        ]),
        tree,
      );
      expect(results, hasLength(1));
      expect(results.single.tierOrder, tier2Order);
      expect(results.single.passed, isTrue);
    });

    test('fails when the layout has drifted from the baseline', () {
      final results = evaluateTier2(
        node([
          const Assertion(type: 'layout_hash', args: {'value': 'sha256:stale'})
        ]),
        _tree([_w('Text')]),
      );
      expect(results.single.passed, isFalse);
      expect(results.single.detail, contains('sha256:stale'));
    });

    test('produces nothing for a node without a layout_hash assertion', () {
      final results = evaluateTier2(
        node([
          const Assertion(type: 'widget_exists', args: {'key': 'x'})
        ]),
        _tree([_w('Text')]),
      );
      expect(results, isEmpty);
    });
  });
}

Rect rectAt(double left, double top) => Rect.fromLTWH(left, top, 100, 40);
