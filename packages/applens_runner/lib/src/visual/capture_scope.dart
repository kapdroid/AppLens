import 'package:applens_core/applens_core.dart';

import '../driver/driver.dart';

/// Tag a node carries to pin full-screen capture regardless of its identity —
/// for composition-critical screens (ARCHITECTURE.md §8).
const String fullScreenCaptureTag = 'capture:full_screen';

/// Derives *where* to capture a tagged node's baseline from the node's own
/// identity — automatic, never hand-chosen per baseline (ARCHITECTURE.md §8):
///
/// * Overlays (dialogs / sheets / snackbars) crop to their **anchor widget**,
///   keyed — so the crop survives layout shifts and, crucially, ignores the
///   full-screen modal barrier that a tree-diff would mistake for the surface.
/// * Route nodes capture the full screen.
/// * A composition-critical node may pin full screen with [fullScreenCaptureTag].
///
/// The anchor → rect resolution happens device-side at capture time (capture.dart
/// reads that widget's `RenderRepaintBoundary`); this function is the pure policy.
CaptureScope deriveCaptureScope(Node node) {
  if (node.payload.tags.contains(fullScreenCaptureTag)) {
    return const FullScreenScope();
  }
  if (node.identity.overlay && node.identity.anchors.isNotEmpty) {
    return WidgetScope(KeySelector(node.identity.anchors.first));
  }
  return const FullScreenScope();
}
