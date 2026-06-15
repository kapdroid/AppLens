import 'dart:typed_data';

import 'package:applens_core/applens_core.dart' show SwipeDirection;

import 'driver.dart';
import 'selector_resolver.dart';

/// A scripted [AppLensDriver] for headless tests: it records every action in
/// [actionLog] and returns pre-recorded tree snapshots in order. This is how the
/// runner/orchestrator (Session 4) is tested without any device.
///
/// Internal: never barrel-exported, so nothing above DriverInterface can name it.
class FakeDriver implements AppLensDriver {
  FakeDriver({List<WidgetTreeSnapshot> trees = const [], Capture? capture})
      : _trees = List.of(trees),
        _capture = capture;

  /// Every action this driver was asked to perform, in order.
  final List<String> actionLog = [];

  final List<WidgetTreeSnapshot> _trees;
  final Capture? _capture;
  int _treeIndex = 0;

  @override
  Future<void> tap(WidgetSelector selector) async =>
      actionLog.add('tap ${describeSelector(selector)}');

  @override
  Future<void> longPress(WidgetSelector selector) async =>
      actionLog.add('longPress ${describeSelector(selector)}');

  @override
  Future<void> enterText(WidgetSelector selector, String text) async =>
      actionLog.add('enterText ${describeSelector(selector)} "$text"');

  @override
  Future<void> scrollTo(WidgetSelector selector) async =>
      actionLog.add('scrollTo ${describeSelector(selector)}');

  @override
  Future<void> swipe(SwipeDirection direction, {WidgetSelector? on}) async =>
      actionLog.add(
          'swipe ${direction.yaml}${on == null ? '' : ' on ${describeSelector(on)}'}');

  @override
  Future<bool> back() async {
    actionLog.add('back');
    // The fake has no real navigator; report "popped" so return-to-start relies
    // on node matching (driven by the scripted fingerprints) to know when it has
    // reached the start, with _maxReturnPops as the backstop.
    return true;
  }

  @override
  Future<void> openDeepLink(Uri uri) async =>
      actionLog.add('openDeepLink $uri');

  @override
  Future<void> settle(SettlePolicy policy) async => actionLog.add('settle');

  @override
  Future<WidgetTreeSnapshot> tree() async {
    if (_trees.isEmpty) {
      return const WidgetTreeSnapshot(SerializedWidget(type: 'Empty'));
    }
    final snapshot = _trees[_treeIndex];
    if (_treeIndex < _trees.length - 1) {
      _treeIndex++;
    }
    return snapshot;
  }

  @override
  Future<Capture> capture(CaptureScope scope) async {
    actionLog.add('capture');
    return _capture ?? Capture(pngBytes: Uint8List(0), width: 0, height: 0);
  }

  @override
  Future<void> native(NativeAction action) async =>
      throw const DriverException('FakeDriver does not support native()');
}
