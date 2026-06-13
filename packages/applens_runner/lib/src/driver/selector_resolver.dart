import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'driver.dart';

/// Converts an AppLens [WidgetSelector] into a flutter_test [Finder]. v1
/// supports keys and semantics labels (ARCHITECTURE.md §17). Driver-internal.
Finder resolveSelector(WidgetSelector selector) => switch (selector) {
      KeySelector(:final key) => find.byKey(ValueKey<String>(key)),
      SemanticsSelector(:final label) => find.bySemanticsLabel(label),
    };

/// A short human description of a selector for diagnostics.
String describeSelector(WidgetSelector selector) => switch (selector) {
      KeySelector(:final key) => 'key "$key"',
      SemanticsSelector(:final label) => 'semantics "$label"',
    };
