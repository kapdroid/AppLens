/// A live observation of app state (ARCHITECTURE.md §7): the current route, the
/// widget keys present (anchor probe), observed flag values, and overlay.
class Fingerprint {
  const Fingerprint({
    this.route,
    this.anchors = const {},
    this.texts = const {},
    this.flags = const {},
    this.overlay = false,
  });

  final String? route;
  final Set<String> anchors;

  /// Plain-text content for each keyed widget (first Text descendant wins).
  final Map<String, String> texts;

  final Map<String, String> flags;
  final bool overlay;
}

/// Assembles the current [Fingerprint]. The production implementation (route via
/// a generated NavigatorObserver, anchors via the driver's tree, flags via SDK
/// introspection or UI inference — ARCHITECTURE.md §7) is wired with the
/// entrypoint in Session 5. The orchestrator depends only on this seam, so its
/// outcome logic is tested headless with a scripted source.
abstract interface class FingerprintSource {
  Future<Fingerprint> capture();
}
