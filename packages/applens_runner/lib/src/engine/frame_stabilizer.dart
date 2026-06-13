import 'dart:typed_data';

/// Whether two captured frames are byte-identical.
bool framesIdentical(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Drives a capture-until-stable loop: pump a frame, capture it, and repeat
/// until [requiredStableFrames] consecutive frames are byte-identical
/// (ARCHITECTURE.md §7 determinism kit). A screen that never settles within
/// [maxAttempts] is its own failure ("node won't settle"), not a pixel diff.
///
/// Pure orchestration: the pump and capture sources are injected, so the loop
/// is unit-tested headless with synthetic frame bytes. Wiring it to real
/// pixels happens with capture (Session 7).
class FrameStabilizer {
  const FrameStabilizer({this.requiredStableFrames = 2, this.maxAttempts = 10});

  /// Consecutive byte-identical frames required to declare stability.
  final int requiredStableFrames;

  /// Upper bound on pump/capture cycles before giving up.
  final int maxAttempts;

  /// Returns true once [requiredStableFrames] consecutive frames match, or
  /// false if [maxAttempts] is exhausted first.
  Future<bool> stabilize({
    required Future<void> Function() pump,
    required Future<Uint8List> Function() capture,
  }) async {
    Uint8List? previous;
    var run = 0;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await pump();
      final frame = await capture();
      if (previous != null && framesIdentical(previous, frame)) {
        run += 1;
      } else {
        run = 1;
      }
      if (run >= requiredStableFrames) {
        return true;
      }
      previous = frame;
    }
    return false;
  }
}
