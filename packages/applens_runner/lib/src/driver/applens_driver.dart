import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'driver.dart';
import 'selector_resolver.dart';

const double _scrollStep = 280;
const int _maxScrolls = 80;

/// The first-party action engine: implements [AppLensDriver] directly on
/// flutter_test primitives (ARCHITECTURE.md §7). Works unchanged under
/// `flutter test` (headless) and `integration_test` (device), since both supply
/// a [WidgetTester]. No Patrol, anywhere.
///
/// Internal: never barrel-exported, so nothing above DriverInterface can name
/// it (enforced by tool/check_boundaries.dart). It is injected at the
/// composition root.
class AppLensWidgetDriver implements AppLensDriver {
  AppLensWidgetDriver(this.tester);

  final WidgetTester tester;

  @override
  Future<void> tap(WidgetSelector selector) async {
    final finder = resolveSelector(selector);
    _ensureSingle(finder, selector);
    _ensureHittable(finder, selector);
    await tester.tap(finder, warnIfMissed: false);
  }

  @override
  Future<void> longPress(WidgetSelector selector) async {
    final finder = resolveSelector(selector);
    _ensureSingle(finder, selector);
    _ensureHittable(finder, selector);
    await tester.longPress(finder, warnIfMissed: false);
  }

  @override
  Future<void> enterText(WidgetSelector selector, String text) async {
    final finder = resolveSelector(selector);
    _ensureSingle(finder, selector);
    // enterText drives the IME through TestTextInput — never synthetic key taps.
    await tester.enterText(finder, text);
  }

  @override
  Future<void> scrollTo(WidgetSelector selector) async {
    final finder = resolveSelector(selector);
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) {
      throw DriverException(
        'scrollTo ${describeSelector(selector)}: no Scrollable on screen',
      );
    }
    final scrollable = tester.widget<Scrollable>(scrollables.first);
    final step = switch (scrollable.axisDirection) {
      AxisDirection.down => const Offset(0, -_scrollStep),
      AxisDirection.up => const Offset(0, _scrollStep),
      AxisDirection.right => const Offset(-_scrollStep, 0),
      AxisDirection.left => const Offset(_scrollStep, 0),
    };
    for (var i = 0; i < _maxScrolls; i++) {
      if (finder.evaluate().isNotEmpty) {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        return;
      }
      await tester.drag(scrollables.first, step);
      await tester.pump();
    }
    throw DriverException(
      'scrollTo could not reveal ${describeSelector(selector)} '
      'after $_maxScrolls scrolls',
    );
  }

  @override
  Future<void> swipe(Offset from, Offset to) async {
    await tester.dragFrom(from, to - from);
    await tester.pump();
  }

  @override
  Future<void> back() async {
    // The in-Flutter equivalent of the system back button: pop the root
    // navigator (honoring PopScope), without the @protected handlePopRoute.
    final navigator = find.byType(Navigator);
    if (navigator.evaluate().isEmpty) {
      throw const DriverException('back(): no Navigator on screen');
    }
    await tester.state<NavigatorState>(navigator.first).maybePop();
  }

  @override
  Future<void> openDeepLink(Uri uri) async {
    // Deep links arrive via the navigation platform channel and route through
    // the app's Router. That wiring lands in a later session; the walking
    // skeleton (and the stranger graph) use no deep_link edges.
    throw UnimplementedError(
      'openDeepLink() is not wired up yet: deep links route through the '
      'navigation platform channel / Router (a later session).',
    );
  }

  @override
  Future<WidgetTreeSnapshot> tree() async {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      throw const DriverException('no widget tree is mounted');
    }
    return WidgetTreeSnapshot(_serialize(root));
  }

  @override
  Future<Capture> capture(CaptureScope scope) async {
    throw UnimplementedError(
      'capture() is wired up in Session 7 (capture.dart): stabilized, scoped '
      'capture with masks. The action engine (Session 3) does not grab pixels.',
    );
  }

  @override
  Future<void> settle(SettlePolicy policy) async {
    // Session 3: bounded pumpAndSettle. The full determinism kit (timeDilation
    // pinning, keyboard policy) and FrameStabilizer wiring land with the
    // orchestrator (Session 4) and capture (Session 7); SettlePolicy's fields
    // are honored there.
    await tester.pumpAndSettle();
  }

  @override
  Future<void> native(NativeAction action) async {
    throw UnimplementedError(
      'native() is unimplemented in v1: permissions are pre-granted from '
      'applens.yaml, not driven. Native flows are a Phase 3 decision '
      '(ARCHITECTURE.md §7).',
    );
  }

  void _ensureSingle(Finder finder, WidgetSelector selector) {
    final matches = finder.evaluate();
    if (matches.isEmpty) {
      throw DriverException('no widget matches ${describeSelector(selector)}');
    }
    if (matches.length > 1) {
      throw DriverException(
        '${matches.length} widgets match ${describeSelector(selector)}; '
        'a selector must be unique',
      );
    }
  }

  /// Verifies the target is the front-most widget at its center, so a tap will
  /// land on it. If something covers it, names the obscuring widget.
  void _ensureHittable(Finder finder, WidgetSelector selector) {
    final center = tester.getCenter(finder);
    final target = tester.renderObject(finder);
    final subtree = <RenderObject>{};
    void collect(RenderObject node) {
      subtree.add(node);
      node.visitChildren(collect);
    }

    collect(target);

    final result = tester.hitTestOnBinding(center);
    for (final entry in result.path) {
      final hit = entry.target;
      if (hit is! RenderObject) {
        continue;
      }
      if (subtree.contains(hit)) {
        return;
      }
      throw DriverException(
        'cannot tap ${describeSelector(selector)}: it is obscured by '
        '${_describeRenderObject(hit)}',
      );
    }
    throw DriverException(
      'cannot tap ${describeSelector(selector)}: nothing is hit-testable at '
      'its center (off-screen?)',
    );
  }

  String _describeRenderObject(RenderObject node) {
    final creator = node.debugCreator;
    if (creator is DebugCreator) {
      return creator.element.widget.runtimeType.toString();
    }
    return node.runtimeType.toString();
  }

  SerializedWidget _serialize(Element element) {
    final children = <SerializedWidget>[];
    element.visitChildren((child) => children.add(_serialize(child)));
    return SerializedWidget(
      type: element.widget.runtimeType.toString(),
      key: _keyOf(element),
      children: children,
    );
  }

  String? _keyOf(Element element) {
    final key = element.widget.key;
    return switch (key) {
      ValueKey<String>(:final value) => value,
      ValueKey(:final value) => (value as Object?)?.toString(),
      _ => null,
    };
  }
}
