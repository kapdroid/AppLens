import '../driver/driver.dart';

/// Produces the observed identity flags for the current state (ARCHITECTURE.md
/// §7/§10) — the values [matchNode] tests a node's `flags:` constraints against
/// and guards read. Two tiers sit behind this one seam: SDK introspection
/// (precise, opt-in — read the app's `AppLensState` via [CallbackFlagSource])
/// and UI inference (zero app integration — [UiInferenceFlagSource]). Returns a
/// flag name → string-value map (the form [FlagConstraint.accepts] consumes).
abstract interface class FlagSource {
  Map<String, String> read(WidgetTreeSnapshot tree);
}

/// No flags — the Tier-0 default that preserves route + anchor-only identity.
class EmptyFlagSource implements FlagSource {
  const EmptyFlagSource();

  @override
  Map<String, String> read(WidgetTreeSnapshot tree) => const {};
}

/// Reads flags from a caller-supplied callback — the bridge the entrypoint uses
/// to expose the app's `applens_sdk` state (`AppLensState.flags`) to the runner,
/// keeping `applens_runner` free of any dependency on `applens_sdk`.
class CallbackFlagSource implements FlagSource {
  const CallbackFlagSource(this._read);

  final Map<String, String> Function() _read;

  @override
  Map<String, String> read(WidgetTreeSnapshot tree) => _read();
}

/// One UI-inference rule: derive a single flag's value from the keys present in
/// the live tree (ARCHITECTURE.md §10 Tier-0). Deterministic; no AI.
sealed class FlagProbe {
  const FlagProbe(this.flag);

  /// The flag name this probe produces.
  final String flag;

  String evaluate(Set<String> keys);
}

/// Counts the keys whose name starts with [prefix] — e.g. `cart_item_` → the
/// cart size, surfaced as the integer flag value an `IntRangeConstraint` reads.
/// The prefix must be unique to the counted items: a sibling key that shares it
/// (e.g. `cart_item_total`) is counted too, so pick a prefix nothing else uses.
class CountProbe extends FlagProbe {
  const CountProbe(super.flag, this.prefix);

  final String prefix;

  @override
  String evaluate(Set<String> keys) =>
      keys.where((k) => k.startsWith(prefix)).length.toString();
}

/// `true` when [key] is present, else `false` — for a boolean-flagged state
/// distinguished by a sentinel widget (e.g. an empty-state label).
class PresenceProbe extends FlagProbe {
  const PresenceProbe(super.flag, this.key);

  final String key;

  @override
  String evaluate(Set<String> keys) => keys.contains(key) ? 'true' : 'false';
}

/// Infers flags from observable widget state — zero app integration. Each probe
/// produces one flag from the set of keys in the tree.
class UiInferenceFlagSource implements FlagSource {
  const UiInferenceFlagSource(this.probes);

  final List<FlagProbe> probes;

  @override
  Map<String, String> read(WidgetTreeSnapshot tree) {
    final keys = <String>{};
    void collect(SerializedWidget w) {
      final key = w.key;
      if (key != null) keys.add(key);
      for (final c in w.children) {
        collect(c);
      }
    }

    collect(tree.root);
    return {for (final probe in probes) probe.flag: probe.evaluate(keys)};
  }
}

/// Merges several sources; a later source wins on a key conflict, so explicit
/// SDK flags override inferred ones (ARCHITECTURE.md §7 "SDK when present, UI
/// inference otherwise").
class CompositeFlagSource implements FlagSource {
  const CompositeFlagSource(this.sources);

  final List<FlagSource> sources;

  @override
  Map<String, String> read(WidgetTreeSnapshot tree) {
    final merged = <String, String>{};
    for (final source in sources) {
      merged.addAll(source.read(tree));
    }
    return merged;
  }
}
