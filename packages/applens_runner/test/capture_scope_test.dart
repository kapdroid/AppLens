import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/src/driver/driver.dart';
import 'package:applens_runner/src/visual/capture_scope.dart';
import 'package:flutter_test/flutter_test.dart';

Node _node({
  bool overlay = false,
  List<String> anchors = const [],
  List<String> tags = const [],
}) =>
    Node(
      id: 'n',
      identity: NodeIdentity(anchors: anchors, overlay: overlay),
      payload: NodePayload(tags: tags),
    );

void main() {
  test('a route node captures the full screen', () {
    expect(
        deriveCaptureScope(_node(anchors: ['screen'])), isA<FullScreenScope>());
  });

  test('an overlay node crops to its anchor widget', () {
    final scope = deriveCaptureScope(_node(overlay: true, anchors: ['dialog']));
    expect(scope, isA<WidgetScope>());
    final selector = (scope as WidgetScope).selector;
    expect(selector, isA<KeySelector>());
    expect((selector as KeySelector).key, 'dialog');
  });

  test('an overlay without a usable anchor falls back to full screen', () {
    expect(deriveCaptureScope(_node(overlay: true)), isA<FullScreenScope>());
  });

  test('the composition-critical tag pins full screen even for an overlay', () {
    expect(
      deriveCaptureScope(
        _node(overlay: true, anchors: ['dialog'], tags: [fullScreenCaptureTag]),
      ),
      isA<FullScreenScope>(),
    );
  });
}
