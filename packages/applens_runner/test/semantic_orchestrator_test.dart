import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:applens_runner/src/driver/fake_driver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _png(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
  return Uint8List.fromList(img.encodePng(image));
}

/// A live tree: a 100×100 frame containing one keyed Text with [liveText].
WidgetTreeSnapshot _liveTree(String liveText) => WidgetTreeSnapshot(
      SerializedWidget(type: 'View', children: [
        SerializedWidget(
          type: 'Frame',
          rect: const Rect.fromLTWH(0, 0, 100, 100),
          children: [
            SerializedWidget(
              type: 'Text',
              key: 'lbl',
              text: liveText,
              rect: const Rect.fromLTWH(10, 10, 40, 10),
            ),
          ],
        ),
      ]),
    );

/// A semantic baseline source returning a fixed snapshot for any baseline.
class _FixedStructural implements StructuralBaselineSource {
  _FixedStructural(this._snapshot);
  final StructuralSnapshot? _snapshot;
  @override
  Future<StructuralSnapshot?> load(StructuralBaseline baseline) async =>
      _snapshot;
}

class _ScriptedFingerprints implements FingerprintSource {
  _ScriptedFingerprints(this._f);
  final Fingerprint _f;
  @override
  Future<Fingerprint> capture() async => _f;
}

StructuralBaseline _approvedBaseline() => const StructuralBaseline(
      context: BaselineContext(device: '', locale: '', theme: ''),
      state: BaselineState.approved,
      snapshot: 'sha256:fixed',
    );

Node _node({WatchSpec? watch}) => Node(
      id: 'S',
      identity: const NodeIdentity(route: '/s', anchors: ['lbl']),
      payload: NodePayload(
        assertions: const [
          Assertion(type: 'widget_exists', args: {'key': 'lbl'}),
        ],
        structuralBaselines: [_approvedBaseline()],
        watch: watch,
      ),
    );

Graph _graph({WatchSpec? watch}) =>
    Graph(nodes: [_node(watch: watch)], entryNodeIds: ['S']);

Plan _plan() => const Plan(
      strategy: PlanStrategy.smoke,
      graphHash: 'h',
      seed: 0,
      paths: [PlanPath(start: 'S')],
    );

StructuralSnapshot _baselineSnap(String text) => StructuralSnapshot([
      WidgetSnapshot(
          type: 'Text',
          key: 'lbl',
          text: text,
          bounds: const NormalizedRect(0.1, 0.1, 0.4, 0.1)),
    ]);

Orchestrator _orch(WidgetTreeSnapshot live, StructuralSnapshot? baseline,
        {WatchSpec? watch}) =>
    Orchestrator(
      driver: FakeDriver(
          trees: [live],
          capture: Capture(pngBytes: _png(100, 100), width: 100, height: 100)),
      fingerprints: _ScriptedFingerprints(
          const Fingerprint(route: '/s', anchors: {'lbl'})),
      store: InMemoryRunStore(),
      structuralBaselines: _FixedStructural(baseline),
    );

void main() {
  test('semantic tier passes when live text matches the baseline', () async {
    final orch =
        _orch(_liveTree('Start shopping'), _baselineSnap('Start shopping'));
    final record = await orch.run(_graph(), _plan());
    final visit = record.visits.single;
    expect(visit.outcome, NodeOutcome.passed);
    final semantic = visit.assertions.where((a) => a.type == 'semantic_match');
    expect(semantic, hasLength(1));
    expect(semantic.first.passed, isTrue);
  });

  test(
      'semantic tier flags a text change as failedSoft, with a localized '
      'annotated artifact', () async {
    final orch = _orch(_liveTree('Start'), _baselineSnap('Start shopping'));
    final record = await orch.run(_graph(), _plan());
    final visit = record.visits.single;
    expect(visit.outcome, NodeOutcome.failedSoft);
    final semantic =
        visit.assertions.firstWhere((a) => a.type == 'semantic_match');
    expect(semantic.passed, isFalse);
    expect(semantic.detail, contains('Start shopping'));
    expect(semantic.detail, contains('"Start"'));
    // The evidence is the annotated screenshot.
    final annotated = visit.artifacts.where((a) => a.kind == 'annotated');
    expect(annotated, hasLength(1));
    expect(annotated.first.bytes, isNotNull);
    expect(img.decodePng(annotated.first.bytes!), isNotNull);
  });

  test('an absent baseline snapshot is skipped, not failed', () async {
    final orch = _orch(_liveTree('whatever'), null);
    final record = await orch.run(_graph(), _plan());
    final visit = record.visits.single;
    expect(visit.outcome, NodeOutcome.passed);
    final semantic =
        visit.assertions.firstWhere((a) => a.type == 'semantic_match');
    expect(semantic.skipped, isTrue);
  });

  test('watch.keys scopes the tier: an unwatched text change does not fail',
      () async {
    // Watch only "other"; the changed widget is "lbl" → no finding.
    final orch = _orch(_liveTree('Start'), _baselineSnap('Start shopping'),
        watch: const WatchSpec(keys: ['other']));
    final record = await orch.run(
        _graph(watch: const WatchSpec(keys: ['other'])), _plan());
    final visit = record.visits.single;
    expect(visit.outcome, NodeOutcome.passed);
  });
}
