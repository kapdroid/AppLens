import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:applens_core/applens_core.dart' show SwipeDirection;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

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

  /// Runs a flutter_test [action], translating a framework failure into a
  /// [DriverException] — the [AppLensDriver] contract's failure type. flutter_test
  /// raises these as `Error`s, not `Exception`s: a `FlutterError` (e.g. a
  /// `pumpAndSettle` timeout on a never-settling screen) or a `StateError` (e.g.
  /// no focused `EditableText` for `enterText`). Both are *driver*-level faults —
  /// the [action] closure only ever calls `tester.*` — so they are contained;
  /// any other `Error` (a real programming bug) is rethrown so it still surfaces.
  Future<T> _guard<T>(String what, Future<T> Function() action) async {
    try {
      return await action();
    } on Error catch (error) {
      if (error is FlutterError || error is StateError) {
        throw DriverException('$what: $error');
      }
      rethrow;
    }
  }

  /// Synchronous [_guard]: the same FlutterError/StateError → [DriverException]
  /// translation for the geometry probes (`getRect`/`getCenter`/`renderObject`),
  /// which raise a `FlutterError` when a keyed target/anchor is not a `RenderBox`
  /// (a valid graph anchor — see `_rectOf`) and must not abort the run.
  T _guardSync<T>(String what, T Function() action) {
    try {
      return action();
    } on Error catch (error) {
      if (error is FlutterError || error is StateError) {
        throw DriverException('$what: $error');
      }
      rethrow;
    }
  }

  @override
  Future<void> tap(WidgetSelector selector) async {
    final finder = resolveSelector(selector);
    _ensureSingle(finder, selector);
    _ensureHittable(finder, selector);
    await _guard('tap ${describeSelector(selector)}',
        () => tester.tap(finder, warnIfMissed: false));
  }

  @override
  Future<void> longPress(WidgetSelector selector) async {
    final finder = resolveSelector(selector);
    _ensureSingle(finder, selector);
    _ensureHittable(finder, selector);
    await _guard('longPress ${describeSelector(selector)}',
        () => tester.longPress(finder, warnIfMissed: false));
  }

  @override
  Future<void> enterText(WidgetSelector selector, String text) async {
    final finder = resolveSelector(selector);
    _ensureSingle(finder, selector);
    // enterText drives the IME through TestTextInput — never synthetic key taps.
    await _guard('enterText ${describeSelector(selector)}',
        () => tester.enterText(finder, text));
  }

  @override
  Future<void> scrollTo(WidgetSelector selector) async {
    final finder = resolveSelector(selector);
    if (find.byType(Scrollable).evaluate().isEmpty) {
      throw DriverException(
        'scrollTo ${describeSelector(selector)}: no Scrollable on screen',
      );
    }
    // A framework FlutterError (e.g. an ensureVisible/pumpAndSettle timeout)
    // becomes a DriverException; the DriverExceptions thrown below pass through.
    await _guard('scrollTo ${describeSelector(selector)}', () async {
      for (var i = 0; i < _maxScrolls; i++) {
        if (finder.evaluate().isNotEmpty) {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          return;
        }
        // Advance every scrollable in its own axis — the one that builds the
        // target reveals it, so we never have to guess which Scrollable is right
        // (a secondary list/carousel before the target's no longer breaks this).
        final scrollables = find.byType(Scrollable);
        for (var s = 0; s < scrollables.evaluate().length; s++) {
          final scrollable = tester.widget<Scrollable>(scrollables.at(s));
          await tester.drag(
              scrollables.at(s),
              switch (scrollable.axisDirection) {
                AxisDirection.down => const Offset(0, -_scrollStep),
                AxisDirection.up => const Offset(0, _scrollStep),
                AxisDirection.right => const Offset(-_scrollStep, 0),
                AxisDirection.left => const Offset(_scrollStep, 0),
              });
        }
        await tester.pump();
      }
      throw DriverException(
        'scrollTo could not reveal ${describeSelector(selector)} '
        'after $_maxScrolls scrolls',
      );
    });
  }

  @override
  Future<void> swipe(SwipeDirection direction, {WidgetSelector? on}) async {
    // Centre on the target widget when named, else the screen centre. The drag
    // distance is a fraction of the gesture's axis so it crosses a page/list
    // boundary without flinging off-screen.
    final ui.Size size =
        tester.view.physicalSize / tester.view.devicePixelRatio;
    final Offset start;
    if (on != null) {
      final finder = resolveSelector(on);
      _ensureSingle(finder, on);
      start = _guardSync(
          'swipe ${describeSelector(on)}', () => tester.getCenter(finder));
      // A widget scrolled out of the viewport still has a center — off-screen —
      // and a fling from there is a silent no-op. Refuse it, like tap refuses an
      // unhittable target, rather than pretend the swipe happened.
      if (start.dx < 0 ||
          start.dy < 0 ||
          start.dx > size.width ||
          start.dy > size.height) {
        throw DriverException(
            'swipe ${describeSelector(on)}: target center $start is off-screen');
      }
    } else {
      start = Offset(size.width / 2, size.height / 2);
    }
    final dx = size.width * 0.4;
    final dy = size.height * 0.4;
    final delta = switch (direction) {
      SwipeDirection.up => Offset(0, -dy),
      SwipeDirection.down => Offset(0, dy),
      SwipeDirection.left => Offset(-dx, 0),
      SwipeDirection.right => Offset(dx, 0),
    };
    // A swipe is a *fling* (velocity-carrying), not a slow drag — so it crosses
    // a PageView/Dismissible snap threshold rather than springing back.
    await _guard('swipe ${direction.yaml}', () async {
      await tester.flingFrom(start, delta, 800);
      await tester.pumpAndSettle();
    });
  }

  @override
  Future<void> back() async {
    // The in-Flutter equivalent of the system back button: pop the root
    // navigator (honoring PopScope), without the @protected handlePopRoute.
    final navigator = find.byType(Navigator);
    if (navigator.evaluate().isEmpty) {
      throw const DriverException('back(): no Navigator on screen');
    }
    await _guard(
        'back', () => tester.state<NavigatorState>(navigator.first).maybePop());
  }

  @override
  Future<void> openDeepLink(Uri uri) async {
    // Deliver the link the way the engine does — the `pushRoute` navigation
    // message — so the app's own Router/Navigator handles it in-process. This
    // driver is test-harness code on WidgetTester, so the `@visibleForTesting`
    // `handlePushRoute` is the right (and only public) in-process entry point.
    // Caveat: a classic `routes:`/`onGenerateRoute` app routes on `uri.path`
    // only (scheme/host dropped) and `handlePushRoute` returns true even for an
    // unresolved route — so `handled` is reliable only for a `Router` backend.
    // The real safety net is the orchestrator re-fingerprinting after: a link
    // that didn't land where expected is a node mismatch, not a false pass.
    await _guard('openDeepLink $uri', () async {
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      final handled = await WidgetsBinding.instance.handlePushRoute('$uri');
      if (!handled) {
        throw DriverException('openDeepLink: app did not handle "$uri"');
      }
      await tester.pumpAndSettle();
    });
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
    if (scope is RegionScope) {
      throw const DriverException(
        'RegionScope capture is not derived in v1: scopes are full-screen or '
        'crop-to-widget (see deriveCaptureScope)',
      );
    }

    // Render the root repaint boundary's layer and encode to PNG — straight
    // (un-premultiplied) alpha, avoiding the premultiplied rawRgba trap of
    // ui.Image.toByteData (ARCHITECTURE.md §8). The layer renders at *physical*
    // resolution (logical × devicePixelRatio), so a crop derived from logical
    // widget rects must scale by DPR (see WidgetScope below).
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      throw const DriverException('no widget tree is mounted to capture');
    }
    final image = await captureImage(root);
    final Uint8List fullPng;
    final int fullWidth;
    final int fullHeight;
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw const DriverException('capture produced no image bytes');
      }
      fullPng = png.buffer.asUint8List();
      fullWidth = image.width;
      fullHeight = image.height;
    } finally {
      image.dispose();
    }

    if (scope is FullScreenScope) {
      return Capture(pngBytes: fullPng, width: fullWidth, height: fullHeight);
    }

    // WidgetScope: crop the full capture to the widget's rect. Cropping the
    // decoded image (rather than layer.toImage on a sub-rect, which deadlocks
    // the headless test binding) keeps an overlay's crop clear of the barrier.
    final selector = (scope as WidgetScope).selector;
    final finder = resolveSelector(selector);
    _ensureSingle(finder, selector);
    // getRect raises a FlutterError when the anchor isn't a RenderBox (a valid
    // overlay anchor — e.g. a keyed Semantics/Builder); surface it as a
    // DriverException so the tier-3 evaluator skips it rather than aborting.
    final rect = _guardSync(
        'capture ${describeSelector(selector)}', () => tester.getRect(finder));
    final decoded = img.decodePng(fullPng)!;
    // The capture is at physical resolution; getRect is logical. Scale the crop
    // by devicePixelRatio so it lands on the widget's pixels at any DPR.
    final dpr = tester.view.devicePixelRatio;
    // Clamp the origin to leave at least one pixel of width/height available, so
    // an anchor at or past the screen edge can't make the width/height clamp see
    // an upper bound below its lower bound (clamp throws when lower > upper).
    final left = (rect.left * dpr).round().clamp(0, decoded.width - 1);
    final top = (rect.top * dpr).round().clamp(0, decoded.height - 1);
    final width = (rect.width * dpr).round().clamp(1, decoded.width - left);
    final height = (rect.height * dpr).round().clamp(1, decoded.height - top);
    final cropped = img.copyCrop(
      decoded,
      x: left,
      y: top,
      width: width,
      height: height,
    );
    return Capture(
      pngBytes: Uint8List.fromList(img.encodePng(cropped)),
      width: cropped.width,
      height: cropped.height,
    );
  }

  @override
  Future<void> settle(SettlePolicy policy) async {
    // Session 3: bounded pumpAndSettle. The full determinism kit (timeDilation
    // pinning, keyboard policy) and FrameStabilizer wiring land with the
    // orchestrator (Session 4) and capture (Session 7); SettlePolicy's fields
    // are honored there. A never-settling screen makes pumpAndSettle time out
    // with a FlutterError — surface it as a DriverException so the orchestrator
    // contains it rather than aborting the whole run.
    await _guard('settle', () => tester.pumpAndSettle());
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

  /// Verifies a tap at the target's center is delivered to the target — its own
  /// subtree (it handles the tap) or an ancestor (an ancestor handler covering
  /// the target, e.g. a keyed transparent wrapper inside a GestureDetector).
  /// Only a front-most node that is neither — a true overlay — is "obscured".
  void _ensureHittable(Finder finder, WidgetSelector selector) {
    final what = 'tap ${describeSelector(selector)}';
    final center = _guardSync(what, () => tester.getCenter(finder));
    final target = _guardSync(what, () => tester.renderObject(finder));

    // Allowing ancestor handlers (above) must not allow a *disabled* region: if
    // an ancestor is an absorbing AbsorbPointer or an ignoring IgnorePointer,
    // that ancestor (or an opaque node behind the ignored subtree) sits in the
    // hit path and would otherwise read as a false pass — a tap that lands but
    // never reaches the target. Treat it as not interactive.
    for (RenderObject? ancestor = target.parent;
        ancestor != null;
        ancestor = ancestor.parent) {
      if ((ancestor is RenderAbsorbPointer && ancestor.absorbing) ||
          (ancestor is RenderIgnorePointer && ancestor.ignoring)) {
        throw DriverException(
          'cannot tap ${describeSelector(selector)}: it is inside a disabled '
          '(${_describeRenderObject(ancestor)}) region',
        );
      }
    }

    final allowed = <RenderObject>{};
    void collect(RenderObject node) {
      allowed.add(node);
      node.visitChildren(collect);
    }

    collect(target);
    for (RenderObject? ancestor = target.parent;
        ancestor != null;
        ancestor = ancestor.parent) {
      allowed.add(ancestor);
    }

    final result = tester.hitTestOnBinding(center);
    for (final entry in result.path) {
      final hit = entry.target;
      if (hit is! RenderObject) {
        continue;
      }
      if (allowed.contains(hit)) {
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
      rect: _rectOf(element),
      text: _textOf(element),
      children: children,
    );
  }

  String? _textOf(Element element) {
    final w = element.widget;
    if (w is Text) {
      return w.data ?? w.textSpan?.toPlainText(includeSemanticsLabels: false);
    }
    if (w is RichText) return w.text.toPlainText(includeSemanticsLabels: false);
    return null;
  }

  /// Global painted bounds for box-backed elements; null for non-box render
  /// objects so the tier-2 layout hash can bucket only real geometry.
  Rect? _rectOf(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox &&
        renderObject.hasSize &&
        renderObject.attached) {
      return renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }
    return null;
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
