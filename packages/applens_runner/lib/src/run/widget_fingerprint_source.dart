import 'package:flutter/widgets.dart';

import '../driver/driver.dart';
import 'fingerprint.dart';

/// Tracks the current route name for fingerprinting (ARCHITECTURE.md §7).
/// Installed in the generated entrypoint's app via `navigatorObservers`.
class AppLensNavigatorObserver extends NavigatorObserver {
  String? currentRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRoute = route.settings.name ?? currentRoute;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRoute = previousRoute?.settings.name ?? currentRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    currentRoute = newRoute?.settings.name ?? currentRoute;
  }
}

/// Assembles a [Fingerprint] from the live app: the route from [observer], the
/// present anchor keys from the driver's serialized tree. Flag-based identity
/// (SDK introspection — applens_sdk) and overlay detection land with the SDK
/// tier (ARCHITECTURE.md §10); v1 reads no flags and assumes no overlay.
class WidgetFingerprintSource implements FingerprintSource {
  WidgetFingerprintSource(this.driver, this.observer);

  final AppLensDriver driver;
  final AppLensNavigatorObserver observer;

  @override
  Future<Fingerprint> capture() async {
    final tree = await driver.tree();
    final anchors = <String>{};
    void collect(SerializedWidget widget) {
      final key = widget.key;
      if (key != null) {
        anchors.add(key);
      }
      for (final child in widget.children) {
        collect(child);
      }
    }

    collect(tree.root);
    return Fingerprint(route: observer.currentRoute, anchors: anchors);
  }
}
