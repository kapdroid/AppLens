/// A predicate over a single identity flag value, parsed from its YAML string
/// form: `true`/`false`, an integer comparison (`>0`, `>=3`, `<5`, `<=2`,
/// `==0`), a bare integer (treated as `==`), or any other literal (exact match).
///
/// Its one job for validation is [contradicts]: deciding whether two
/// constraints on the *same* flag can both hold. If no flag distinguishes two
/// otherwise-identical nodes, they are fingerprint-ambiguous — the most
/// important error AppLens detects (ARCHITECTURE.md §4).
sealed class FlagConstraint {
  const FlagConstraint(this.raw);

  /// The original YAML spelling, preserved for round-tripping.
  final String raw;

  /// Parses the YAML string form of a flag constraint.
  factory FlagConstraint.parse(String input) {
    final text = input.trim();
    if (text == 'true') {
      return const BoolConstraint(true, 'true');
    }
    if (text == 'false') {
      return const BoolConstraint(false, 'false');
    }
    final comparison = _comparison.firstMatch(text);
    if (comparison != null) {
      final op = comparison.group(1)!;
      final n = int.parse(comparison.group(2)!);
      return switch (op) {
        '>' => IntRangeConstraint(low: n + 1, high: null, raw: text),
        '>=' => IntRangeConstraint(low: n, high: null, raw: text),
        '<' => IntRangeConstraint(low: null, high: n - 1, raw: text),
        '<=' => IntRangeConstraint(low: null, high: n, raw: text),
        _ => IntRangeConstraint(low: n, high: n, raw: text), // ==
      };
    }
    final bare = int.tryParse(text);
    if (bare != null) {
      return IntRangeConstraint(low: bare, high: bare, raw: text);
    }
    return ExactConstraint(text);
  }

  /// Whether [other] (a constraint on the same flag key) can hold at the same
  /// time as this one. Contradicting constraints make their nodes
  /// distinguishable; jointly satisfiable ones do not.
  bool contradicts(FlagConstraint other);

  /// Whether an observed runtime flag [value] (its string form) satisfies this
  /// constraint — used by the runner to match a live state to a node.
  bool accepts(String value);

  static final RegExp _comparison = RegExp(r'^(>=|<=|==|>|<)\s*(-?\d+)$');
}

/// A boolean flag constraint (`true` / `false`).
class BoolConstraint extends FlagConstraint {
  const BoolConstraint(this.value, String raw) : super(raw);

  final bool value;

  @override
  bool contradicts(FlagConstraint other) =>
      other is! BoolConstraint || other.value != value;

  @override
  bool accepts(String observed) => switch (observed) {
        'true' => value == true,
        'false' => value == false,
        _ => false,
      };
}

/// An inclusive integer range, with `null` bounds meaning unbounded.
class IntRangeConstraint extends FlagConstraint {
  const IntRangeConstraint(
      {required this.low, required this.high, required String raw})
      : super(raw);

  final int? low;
  final int? high;

  @override
  bool contradicts(FlagConstraint other) {
    if (other is! IntRangeConstraint) {
      return true;
    }
    final lo = _max(low, other.low);
    final hi = _min(high, other.high);
    if (lo == null || hi == null) {
      return false; // At least one side unbounded — they always overlap.
    }
    return lo > hi; // Disjoint ranges contradict.
  }

  @override
  bool accepts(String observed) {
    final n = int.tryParse(observed);
    if (n == null) {
      return false;
    }
    return (low == null || n >= low!) && (high == null || n <= high!);
  }

  static int? _max(int? a, int? b) =>
      a == null ? b : (b == null ? a : (a > b ? a : b));
  static int? _min(int? a, int? b) =>
      a == null ? b : (b == null ? a : (a < b ? a : b));
}

/// An exact, non-numeric, non-boolean literal match.
class ExactConstraint extends FlagConstraint {
  const ExactConstraint(this.value) : super(value);

  final String value;

  @override
  bool contradicts(FlagConstraint other) =>
      other is! ExactConstraint || other.value != value;

  @override
  bool accepts(String observed) => observed == value;
}
