import 'package:applens_core/applens_core.dart';

import '../driver/driver.dart';

/// Tag a node carries to pin full-screen capture regardless of its identity —
/// for composition-critical screens (ARCHITECTURE.md §8).
const String fullScreenCaptureTag = 'capture:full_screen';

/// Derives *where* to capture a tagged node's baseline from the node's own
/// identity — automatic, never hand-chosen per baseline (ARCHITECTURE.md §8):
///
/// * Overlays (dialogs / sheets / snackbars) crop to their **anchor widget** —
///   keyed, so the crop survives layout shifts; because the anchor resolves to
///   the overlay's own keyed root (never the unkeyed modal barrier), the crop
///   stays clear of the barrier.
/// * Route nodes capture the full screen.
/// * A composition-critical node may pin full screen with [fullScreenCaptureTag].
///
/// The anchor → rect resolution happens device-side at capture time: capture()
/// crops the full-screen capture to that widget's painted bounds
/// (`tester.getRect`). This function is the pure policy.
/// The recorded [CaptureKind] for a derived [scope] — the form stored on a
/// [VisualBaseline] so a recapture is compared at the same scope it was taken.
CaptureKind captureKindOf(CaptureScope scope) => switch (scope) {
      FullScreenScope() => CaptureKind.fullScreen,
      WidgetScope() => CaptureKind.cropToWidget,
      RegionScope() => CaptureKind.region,
    };

CaptureScope deriveCaptureScope(Node node) {
  if (node.payload.tags.contains(fullScreenCaptureTag)) {
    return const FullScreenScope();
  }
  if (node.identity.overlay && node.identity.anchors.isNotEmpty) {
    return WidgetScope(KeySelector(node.identity.anchors.first));
  }
  return const FullScreenScope();
}
