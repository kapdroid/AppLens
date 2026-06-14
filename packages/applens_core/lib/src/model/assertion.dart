import '../util/canonical.dart';

/// A node assertion (ARCHITECTURE.md §4). [type] selects the check
/// (`widget_exists`, `text_equals`, `layout_hash`, …) and [args] carries its
/// type-specific fields (`key`, `source`, `baseline`, `value`, …). Kept
/// open-typed rather than over-modeled — assertion kinds are tier-specific and
/// extensible.
class Assertion {
  const Assertion({required this.type, this.args = const {}});

  final String type;
  final Map<String, Object?> args;

  Map<String, Object?> toMap() => {'type': type, ...args};
}

/// Where a visual baseline is cropped (ARCHITECTURE.md §8). Derived from the
/// tree diff at capture time, not hand-chosen.
enum CaptureKind {
  fullScreen('full_screen'),
  cropToWidget('crop_to_widget'),
  region('region');

  const CaptureKind(this.yaml);
  final String yaml;

  static CaptureKind? fromYaml(String value) {
    for (final kind in CaptureKind.values) {
      if (kind.yaml == value) {
        return kind;
      }
    }
    return null;
  }
}

/// The lifecycle state of a visual baseline (ARCHITECTURE.md §9).
enum BaselineState {
  approved,
  proposed,
  rejected;

  static BaselineState? fromYaml(String value) {
    for (final state in BaselineState.values) {
      if (state.name == value) {
        return state;
      }
    }
    return null;
  }
}

/// The (device, locale, theme) a baseline was captured under.
class BaselineContext {
  const BaselineContext({
    required this.device,
    required this.locale,
    required this.theme,
  });

  final String device;
  final String locale;
  final String theme;

  Map<String, Object?> toMap() => {
        'device': device,
        'locale': locale,
        'theme': theme,
      };

  factory BaselineContext.fromMap(Map<String, Object?> map) => BaselineContext(
        device: map['device']! as String,
        locale: map['locale']! as String,
        theme: map['theme']! as String,
      );
}

/// A tier-3 visual baseline keyed by (node, device, locale, theme),
/// content-addressed (ARCHITECTURE.md §4/§8). Tagged nodes only.
class VisualBaseline {
  const VisualBaseline({
    required this.context,
    required this.capture,
    required this.state,
    this.widget,
    this.image,
    this.mask,
    this.threshold,
    this.approvedBy,
    this.reasonPr,
    this.replaced,
  });

  final BaselineContext context;
  final CaptureKind capture;
  final BaselineState state;
  final String? widget;
  final String? image; // sha256:...
  final String? mask;
  final double? threshold;
  final String? approvedBy;
  final String? reasonPr;
  final String? replaced; // retired hash, for the audit trail

  Map<String, Object?> toMap() => compactMap({
        'context': context.toMap(),
        'capture': capture.yaml,
        'state': state.name,
        'widget': widget,
        'image': image,
        'mask': mask,
        'threshold': threshold,
        'approved_by': approvedBy,
        'reason_pr': reasonPr,
        'replaced': replaced,
      });

  factory VisualBaseline.fromMap(Map<String, Object?> map) => VisualBaseline(
        context: BaselineContext.fromMap(
            (map['context']! as Map).cast<String, Object?>()),
        // Throw on an unknown enum rather than silently coercing — a corrupted
        // `state`/`capture` must not quietly downgrade a baseline.
        capture: CaptureKind.fromYaml(map['capture']! as String) ??
            (throw FormatException('unknown capture "${map['capture']}"')),
        state: BaselineState.fromYaml(map['state']! as String) ??
            (throw FormatException('unknown baseline state "${map['state']}"')),
        widget: map['widget'] as String?,
        image: map['image'] as String?,
        mask: map['mask'] as String?,
        threshold: (map['threshold'] as num?)?.toDouble(),
        approvedBy: map['approved_by'] as String?,
        reasonPr: map['reason_pr'] as String?,
        replaced: map['replaced'] as String?,
      );
}
