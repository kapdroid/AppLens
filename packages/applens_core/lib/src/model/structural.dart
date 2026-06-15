import 'dart:math' as math;

import '../util/canonical.dart';
import 'assertion.dart';

/// A widget's painted bounds normalized to the captured screen (each component
/// in 0..1, relative to the root's bounds), so the semantic tier compares
/// geometry independent of device resolution and DPR (ARCHITECTURE.md §8).
class NormalizedRect {
  const NormalizedRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  /// Center-to-center distance to [other], in normalized units (0..~1.4).
  double distanceTo(NormalizedRect other) {
    final dx = (left + width / 2) - (other.left + other.width / 2);
    final dy = (top + height / 2) - (other.top + other.height / 2);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// True when this rect differs from [other] by more than [tolerance] in any
  /// edge — the geometry-change predicate. [tolerance] is in normalized units.
  bool differsFrom(NormalizedRect other, double tolerance) =>
      (left - other.left).abs() > tolerance ||
      (top - other.top).abs() > tolerance ||
      (width - other.width).abs() > tolerance ||
      (height - other.height).abs() > tolerance;

  List<double> toList() => [left, top, width, height];

  factory NormalizedRect.fromList(List<Object?> list) => NormalizedRect(
        (list[0]! as num).toDouble(),
        (list[1]! as num).toDouble(),
        (list[2]! as num).toDouble(),
        (list[3]! as num).toDouble(),
      );
}

/// One identifiable widget in a semantic snapshot: its key (if any), runtime
/// type, plain text (for Text/RichText), and normalized bounds. Widgets with
/// neither a key nor text are not snapshotted — they carry no diff-worthy
/// identity (ARCHITECTURE.md §8 tier 2.5).
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.type,
    required this.bounds,
    this.key,
    this.text,
  });

  final String type;
  final NormalizedRect bounds;
  final String? key;
  final String? text;

  Map<String, Object?> toMap() => compactMap({
        'type': type,
        'key': key,
        'text': text,
        'bounds': bounds.toList(),
      });

  factory WidgetSnapshot.fromMap(Map<String, Object?> map) => WidgetSnapshot(
        type: map['type']! as String,
        bounds: NormalizedRect.fromList((map['bounds']! as List).cast()),
        key: map['key'] as String?,
        text: map['text'] as String?,
      );
}

/// The recorded semantic appearance of a node — the list of identifiable
/// widgets with their text and geometry. Content-addressed: stored as a JSON
/// file under `structural/<hex>.json` and referenced from the node by
/// [StructuralBaseline.snapshot], exactly as goldens are (ARCHITECTURE.md §8).
class StructuralSnapshot {
  const StructuralSnapshot(this.widgets);

  final List<WidgetSnapshot> widgets;

  Map<String, Object?> toMap() => {
        'widgets': [for (final w in widgets) w.toMap()],
      };

  /// The deterministic `sha256:<hex>` key for this snapshot — the value stored
  /// in [StructuralBaseline.snapshot] and the filename stem under `structural/`.
  String get key => contentHash(toMap());

  factory StructuralSnapshot.fromMap(Map<String, Object?> map) =>
      StructuralSnapshot([
        for (final w in (map['widgets']! as List))
          WidgetSnapshot.fromMap((w as Map).cast<String, Object?>()),
      ]);
}

/// A tier-2.5 semantic baseline keyed by (node, device, locale, theme),
/// content-addressed like [VisualBaseline]. Tracks the node's recorded widget
/// text + geometry so a later run can detect (and localize) a text or alignment
/// change. Tagged/watched nodes only.
class StructuralBaseline {
  const StructuralBaseline({
    required this.context,
    required this.state,
    this.snapshot,
    this.approvedBy,
    this.reasonPr,
    this.replaced,
  });

  final BaselineContext context;
  final BaselineState state;
  final String? snapshot; // sha256:... → structural/<hex>.json
  final String? approvedBy;
  final String? reasonPr;
  final String? replaced;

  Map<String, Object?> toMap() => compactMap({
        'context': context.toMap(),
        'state': state.name,
        'snapshot': snapshot,
        'approved_by': approvedBy,
        'reason_pr': reasonPr,
        'replaced': replaced,
      });

  factory StructuralBaseline.fromMap(Map<String, Object?> map) =>
      StructuralBaseline(
        context: BaselineContext.fromMap(
            (map['context']! as Map).cast<String, Object?>()),
        state: BaselineState.fromYaml(map['state']! as String) ??
            (throw FormatException('unknown baseline state "${map['state']}"')),
        snapshot: map['snapshot'] as String?,
        approvedBy: map['approved_by'] as String?,
        reasonPr: map['reason_pr'] as String?,
        replaced: map['replaced'] as String?,
      );
}

/// A node's opt-in declaration of what the semantic tier should watch
/// (ARCHITECTURE.md §8). When [keys] is non-empty only those keyed widgets are
/// diffed; when empty every identifiable widget is auto-tracked. [text] and
/// [layout] toggle the two diff dimensions. Absent from a node ⇒ the tier is
/// off for that node unless it carries a structural baseline.
class WatchSpec {
  const WatchSpec({
    this.keys = const [],
    this.text = true,
    this.layout = true,
  });

  final List<String> keys;
  final bool text;
  final bool layout;

  bool watches(String? key) =>
      keys.isEmpty || (key != null && keys.contains(key));

  Map<String, Object?> toMap() => compactMap({
        'keys': keys,
        // Defaults (true) are dropped so an empty `watch: {}` round-trips clean.
        'text': text ? null : false,
        'layout': layout ? null : false,
      });

  factory WatchSpec.fromMap(Map<String, Object?> map) => WatchSpec(
        keys: [for (final k in (map['keys'] as List? ?? const [])) k as String],
        text: map['text'] as bool? ?? true,
        layout: map['layout'] as bool? ?? true,
      );
}
