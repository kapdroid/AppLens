import 'dart:typed_data';
import 'dart:ui';

/// The single seam between AppLens and any UI-driving backend. NOTHING above
/// this interface may import a concrete driver — enforced by
/// tool/check_boundaries.dart. v1 ships a first-party engine on Flutter SDK
/// APIs (Session 3); Patrol appears nowhere.
abstract interface class AppLensDriver {
  /// Taps the widget matched by [selector], after verifying it is hit-testable.
  Future<void> tap(WidgetSelector selector);

  /// Long-presses the widget matched by [selector].
  Future<void> longPress(WidgetSelector selector);

  /// Enters [text] into the field matched by [selector] via IME emulation
  /// (never synthetic key taps).
  Future<void> enterText(WidgetSelector selector, String text);

  /// Scrolls until the widget matched by [selector] is visible, respecting
  /// scroll physics and nested scrollables.
  Future<void> scrollTo(WidgetSelector selector);

  /// Drags from [from] to [to] in logical pixels.
  Future<void> swipe(Offset from, Offset to);

  /// Pops the current route (in-Flutter back).
  Future<void> back();

  /// Opens [uri] as a deep link through the platform channel.
  Future<void> openDeepLink(Uri uri);

  /// Returns a serialized snapshot of the current widget tree, used for
  /// fingerprinting and tier-1/2 oracles.
  Future<WidgetTreeSnapshot> tree();

  /// Captures the screen at the given [scope].
  Future<Capture> capture(CaptureScope scope);

  /// Waits until the UI is stable per [policy].
  Future<void> settle(SettlePolicy policy);

  /// Native OS surfaces (permission dialogs, notifications).
  ///
  /// v1 throws [UnimplementedError]: permissions are pre-granted from
  /// applens.yaml rather than automated (docs/ARCHITECTURE.md §7). Native flows
  /// are a Phase 3 decision gated on the dependency ladder (§14).
  Future<void> native(NativeAction action);
}

/// How the driver locates a widget. v1 supports keys and semantics labels — no
/// text matching (docs/ARCHITECTURE.md §17).
sealed class WidgetSelector {
  const WidgetSelector();
}

/// Selects a widget by its value-key string.
class KeySelector extends WidgetSelector {
  const KeySelector(this.key);
  final String key;
}

/// Selects a widget by its semantics [label].
class SemanticsSelector extends WidgetSelector {
  const SemanticsSelector(this.label);
  final String label;
}

/// An immutable, serializable view of the element tree.
class WidgetTreeSnapshot {
  const WidgetTreeSnapshot(this.root);
  final SerializedWidget root;
}

/// One node in a [WidgetTreeSnapshot].
class SerializedWidget {
  const SerializedWidget({
    required this.type,
    this.key,
    this.children = const <SerializedWidget>[],
  });

  final String type;
  final String? key;
  final List<SerializedWidget> children;
}

/// A captured image in straight (un-premultiplied) RGBA byte order — the layout
/// the pixelmatch port expects (docs/ARCHITECTURE.md §8).
class Capture {
  const Capture({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// What region a [AppLensDriver.capture] grabs. Scope is derived from the tree
/// diff at capture time, not hand-chosen (docs/ARCHITECTURE.md §8).
sealed class CaptureScope {
  const CaptureScope();
}

/// The whole screen.
class FullScreenScope extends CaptureScope {
  const FullScreenScope();
}

/// Just the widget matched by [selector] (its repaint boundary).
class WidgetScope extends CaptureScope {
  const WidgetScope(this.selector);
  final WidgetSelector selector;
}

/// An explicit rectangular region.
class RegionScope extends CaptureScope {
  const RegionScope(this.rect);
  final Rect rect;
}

/// How long and how strictly to wait for the UI to stabilize before observing.
class SettlePolicy {
  const SettlePolicy({
    this.timeout = const Duration(seconds: 10),
    this.stableFrames = 2,
    this.keyboardUp = false,
  });

  /// Upper bound on settling; a screen that never settles is its own failure.
  final Duration timeout;

  /// Consecutive byte-identical frames required to declare stability.
  final int stableFrames;

  /// Whether the keyboard is expected to remain visible.
  final bool keyboardUp;
}

/// A native OS action requested through [AppLensDriver.native].
sealed class NativeAction {
  const NativeAction();
}

/// Grant or interact with a runtime permission dialog.
class PermissionAction extends NativeAction {
  const PermissionAction(this.permission);
  final String permission;
}

/// Tap a system notification by its [title].
class NotificationAction extends NativeAction {
  const NotificationAction(this.title);
  final String title;
}
