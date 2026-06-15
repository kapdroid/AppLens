import 'package:flutter/foundation.dart' show kReleaseMode;

/// The optional in-app state registry for AppLens Tier-1 integration
/// (ARCHITECTURE.md §10). The app records cheap state probes — `cart_count`,
/// `journey.started`, feature-flag values — that the runner reads as identity
/// flags (`flags: { cart_count: ">0" }`) and guards (`requires: [...]`),
/// enabling precise state-based identity that UI inference can only approximate.
///
/// Debug-only by construction: every mutation is a no-op in release builds, so
/// the calls a host app sprinkles in its widgets compile out of shipping
/// binaries — the SDK adds nothing to production. The runner reads [flags]
/// through a `CallbackFlagSource(() => AppLensState.flags)` in the entrypoint,
/// so `applens_runner` never depends on this package.
class AppLensState {
  AppLensState._();

  static final Map<String, String> _flags = {};

  /// Records [name] = [value] (stringified to the form `FlagConstraint` reads —
  /// `true`/`false` for bools, the decimal for ints). No-op in release.
  static void setFlag(String name, Object value) {
    if (kReleaseMode) return;
    _flags[name] = '$value';
  }

  /// Removes one flag — for a screen that tears down the state it advertised.
  /// No-op in release.
  static void clearFlag(String name) {
    if (kReleaseMode) return;
    _flags.remove(name);
  }

  /// Clears all flags — the seed/reset hook the runner can invoke to return the
  /// app to a known state between paths. No-op in release.
  static void reset() {
    if (kReleaseMode) return;
    _flags.clear();
  }

  /// The current flags, as the runner's flag source reads them. Always empty in
  /// release (nothing was ever recorded).
  static Map<String, String> get flags => Map.unmodifiable(_flags);
}
