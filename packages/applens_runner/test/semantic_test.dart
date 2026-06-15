import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:applens_runner/src/driver/applens_driver.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

WidgetSnapshot _w(
  String type, {
  String? key,
  String? text,
  NormalizedRect bounds = const NormalizedRect(0, 0, 0.1, 0.1),
}) =>
    WidgetSnapshot(type: type, key: key, text: text, bounds: bounds);

void main() {
  group('matchWidgets', () {
    test('pairs by key first, even when the widget moved', () {
      final base = [
        _w('ElevatedButton',
            key: 'btn',
            text: 'Go',
            bounds: const NormalizedRect(0.1, 0.1, 0.2, 0.05)),
      ];
      final curr = [
        _w('ElevatedButton',
            key: 'btn',
            text: 'Go',
            bounds: const NormalizedRect(0.5, 0.8, 0.2, 0.05)),
      ];
      final m = matchWidgets(base, curr);
      expect(m.pairs, hasLength(1));
      expect(m.added, isEmpty);
      expect(m.removed, isEmpty);
      expect(m.pairs.first.$1.key, 'btn');
    });

    test('pairs unkeyed widgets by unique (type, text)', () {
      final base = [
        _w('Text',
            text: 'Welcome', bounds: const NormalizedRect(0, 0, 0.3, 0.05))
      ];
      final curr = [
        _w('Text',
            text: 'Welcome', bounds: const NormalizedRect(0, 0.4, 0.3, 0.05))
      ];
      final m = matchWidgets(base, curr);
      expect(m.pairs, hasLength(1));
      expect(m.removed, isEmpty);
    });

    test('does not pair unkeyed widgets when (type,text) is ambiguous', () {
      final base = [_w('Text', text: 'Item'), _w('Text', text: 'Item')];
      final curr = [_w('Text', text: 'Item'), _w('Text', text: 'Item')];
      final m = matchWidgets(base, curr);
      // ambiguous → not paired; reported as removed/added rather than guessed
      expect(m.pairs, isEmpty);
      expect(m.removed, hasLength(2));
      expect(m.added, hasLength(2));
    });

    test('a removed key is reported, not mispaired by text', () {
      final base = [_w('Text', key: 'gone', text: 'X')];
      final curr = [_w('Text', key: 'other', text: 'X')];
      final m = matchWidgets(base, curr);
      // keys differ; rung-2 then pairs them by unique (Text,'X')
      expect(m.pairs, hasLength(1));
    });
  });

  group('diffStructural', () {
    test('detects a text change on a keyed widget', () {
      final base = [_w('ElevatedButton', key: 'btn', text: 'Start shopping')];
      final curr = [_w('ElevatedButton', key: 'btn', text: 'Start')];
      final findings = diffStructural(matchWidgets(base, curr));
      expect(findings, hasLength(1));
      expect(findings.first.kind, FindingKind.textChanged);
      expect(findings.first.describe(), contains('Start shopping'));
      expect(findings.first.describe(), contains('"Start"'));
    });

    test('detects a move beyond tolerance, ignores jitter within it', () {
      final base = [
        _w('Icon', key: 'i', bounds: const NormalizedRect(0.1, 0.1, 0.05, 0.05))
      ];
      final jitter = [
        _w('Icon',
            key: 'i', bounds: const NormalizedRect(0.105, 0.1, 0.05, 0.05))
      ];
      final moved = [
        _w('Icon', key: 'i', bounds: const NormalizedRect(0.4, 0.1, 0.05, 0.05))
      ];
      expect(diffStructural(matchWidgets(base, jitter)), isEmpty);
      final f = diffStructural(matchWidgets(base, moved));
      expect(f, hasLength(1));
      expect(f.first.kind, FindingKind.moved);
    });

    test('watch.keys scopes which widgets are diffed', () {
      final base = [
        _w('Text', key: 'a', text: 'one'),
        _w('Text', key: 'b', text: 'two'),
      ];
      final curr = [
        _w('Text', key: 'a', text: 'ONE'),
        _w('Text', key: 'b', text: 'TWO'),
      ];
      final m = matchWidgets(base, curr);
      final scoped = diffStructural(m, watch: const WatchSpec(keys: ['a']));
      expect(scoped, hasLength(1));
      expect(scoped.first.key, 'a');
    });

    test('watch_text:false suppresses text findings but keeps layout', () {
      final base = [
        _w('Text',
            key: 'a',
            text: 'one',
            bounds: const NormalizedRect(0, 0, 0.2, 0.05))
      ];
      final curr = [
        _w('Text',
            key: 'a',
            text: 'two',
            bounds: const NormalizedRect(0.5, 0, 0.2, 0.05))
      ];
      final m = matchWidgets(base, curr);
      final findings = diffStructural(m, watch: const WatchSpec(text: false));
      expect(findings.map((f) => f.kind), [FindingKind.moved]);
    });

    test('an explicitly-watched key that vanished is reported as removed', () {
      final base = [_w('ElevatedButton', key: 'btn_pay', text: 'Pay')];
      final curr = <WidgetSnapshot>[];
      final m = matchWidgets(base, curr);
      final findings =
          diffStructural(m, watch: const WatchSpec(keys: ['btn_pay']));
      expect(findings, hasLength(1));
      expect(findings.first.kind, FindingKind.removed);
    });

    test('no false findings when nothing changed', () {
      final snap = [
        _w('ElevatedButton',
            key: 'btn',
            text: 'Go',
            bounds: const NormalizedRect(0.1, 0.1, 0.2, 0.05)),
        _w('Text',
            text: 'Welcome', bounds: const NormalizedRect(0, 0, 0.3, 0.05)),
      ];
      expect(diffStructural(matchWidgets(snap, snap)), isEmpty);
    });
  });

  group('captureStructural', () {
    testWidgets(
        'keyed widgets carry their text + normalized bounds; nested '
        'unkeyed Text is folded into the keyed entry', (tester) async {
      // Pin a known surface so the normalization frame is a deterministic 400×800.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
            child: Stack(children: const [
              Positioned(
                left: 40,
                top: 80,
                width: 200,
                height: 40,
                child: ColoredBox(
                  color: Color(0xFF000000),
                  child: Text('Start shopping',
                      key: Key('btn_start'), textDirection: TextDirection.ltr),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                width: 100,
                height: 20,
                child: Text('Welcome', textDirection: TextDirection.ltr),
              ),
            ]),
          ),
        ),
      );

      final driver = AppLensWidgetDriver(tester);
      final snap = captureStructural(await driver.tree());

      final keyed = snap.widgets.where((w) => w.key == 'btn_start').toList();
      expect(keyed, hasLength(1), reason: 'the keyed widget is captured once');
      expect(keyed.first.text, 'Start shopping',
          reason: 'keyed widget folds in its child Text');
      // No separate unkeyed Text entry for the text *inside* the keyed widget.
      expect(
          snap.widgets
              .where((w) => w.key == null && w.text == 'Start shopping'),
          isEmpty);
      // The unkeyed Text outside any keyed widget is captured on its own.
      expect(snap.widgets.where((w) => w.key == null && w.text == 'Welcome'),
          hasLength(1));

      // Bounds are normalized to the 400×800 frame (0..1).
      final b = keyed.first.bounds;
      expect(b.left, closeTo(40 / 400, 0.01));
      expect(b.top, closeTo(80 / 800, 0.01));
      expect(b.width, closeTo(200 / 400, 0.01));
    });
  });
}
