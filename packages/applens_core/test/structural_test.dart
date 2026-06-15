import 'package:applens_core/applens_core.dart';
import 'package:test/test.dart';

void main() {
  group('NormalizedRect', () {
    test('differsFrom respects tolerance per edge', () {
      const a = NormalizedRect(0.1, 0.1, 0.2, 0.05);
      // within tolerance on every edge → not different
      expect(a.differsFrom(const NormalizedRect(0.105, 0.1, 0.2, 0.05), 0.01),
          isFalse);
      // left moved beyond tolerance → different
      expect(a.differsFrom(const NormalizedRect(0.13, 0.1, 0.2, 0.05), 0.01),
          isTrue);
    });

    test('round-trips through toList/fromList', () {
      const a = NormalizedRect(0.1, 0.2, 0.3, 0.4);
      final b = NormalizedRect.fromList(a.toList());
      expect([b.left, b.top, b.width, b.height], [0.1, 0.2, 0.3, 0.4]);
    });
  });

  group('StructuralSnapshot', () {
    test('round-trips and is content-addressed stably', () {
      final snap = StructuralSnapshot([
        const WidgetSnapshot(
          type: 'ElevatedButton',
          key: 'btn_start',
          text: 'Start shopping',
          bounds: NormalizedRect(0.1, 0.1, 0.3, 0.06),
        ),
        const WidgetSnapshot(
          type: 'Text',
          text: 'Welcome',
          bounds: NormalizedRect(0.1, 0.02, 0.2, 0.04),
        ),
      ]);
      final round = StructuralSnapshot.fromMap(snap.toMap());
      expect(round.widgets, hasLength(2));
      expect(round.widgets.first.key, 'btn_start');
      expect(round.widgets.first.text, 'Start shopping');
      expect(round.widgets[1].key, isNull);
      // same content → same key, independent of construction
      expect(round.key, snap.key);
      expect(snap.key, startsWith('sha256:'));
    });

    test('a text change yields a different key', () {
      final a = StructuralSnapshot([
        const WidgetSnapshot(
            type: 'Text',
            text: 'Start shopping',
            bounds: NormalizedRect(0, 0, 1, 1)),
      ]);
      final b = StructuralSnapshot([
        const WidgetSnapshot(
            type: 'Text', text: 'Start', bounds: NormalizedRect(0, 0, 1, 1)),
      ]);
      expect(a.key, isNot(b.key));
    });
  });

  group('node payload round-trip', () {
    test('structural_baselines and watch survive parse→serialize→parse', () {
      const yaml = '''
identity:
  route: /home
  anchors: [btn_start]
payload:
  assertions:
    - { type: widget_exists, key: btn_start }
  structural_baselines:
    - context: { device: emu, locale: en, theme: light }
      state: approved
      snapshot: "sha256:abc123"
  watch:
    keys: [btn_start, lbl_welcome]
    layout: false
  tags: [sanity]
''';
      final node = parseNode(yaml, source: 'home.yaml', assignedId: 'home');
      expect(node.payload.structuralBaselines, hasLength(1));
      final sb = node.payload.structuralBaselines.first;
      expect(sb.state, BaselineState.approved);
      expect(sb.snapshot, 'sha256:abc123');
      expect(sb.context.device, 'emu');

      final watch = node.payload.watch!;
      expect(watch.keys, ['btn_start', 'lbl_welcome']);
      expect(watch.text, isTrue);
      expect(watch.layout, isFalse);
      expect(watch.watches('btn_start'), isTrue);
      expect(watch.watches('other'), isFalse);

      // Re-parse from the serialized map to prove the round trip.
      final reparsed =
          parseNode(_emitYaml(node), source: 'home.yaml', assignedId: 'home');
      expect(
          reparsed.payload.structuralBaselines.first.snapshot, 'sha256:abc123');
      expect(reparsed.payload.watch!.layout, isFalse);
    });

    test('an unknown structural baseline state is a loud parse error', () {
      const yaml = '''
identity:
  route: /home
payload:
  structural_baselines:
    - context: { device: emu, locale: en, theme: light }
      state: aproved
      snapshot: "sha256:abc"
''';
      expect(
        () => parseNode(yaml, source: 'home.yaml', assignedId: 'home'),
        throwsA(isA<GraphParseException>()),
      );
    });
  });
}

String _emitYaml(Node node) => writeYaml({
      'identity': node.identity.toMap(),
      'payload': node.payload.toMap(),
    });
