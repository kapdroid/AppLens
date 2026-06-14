import 'package:flutter/widgets.dart';

import '../driver/driver.dart';
import 'fingerprint.dart';

/// Tracks the current route for fingerprinting (ARCHITECTURE.md §7) by mirroring
/// the navigator's route stack, so the route is correct after pop, replace, and
/// removeRoute — not just push. Installed in the generated entrypoint's app via
/// `navigatorObservers`. [currentRoute] is the top route's name, or null when
/// the top route is unnamed (honest — a fingerprint then matches on anchors,
/// rather than inheriting a stale previous route's name).
class AppLensNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  String? get currentRoute => _stack.isEmpty ? null : _stack.last.settings.name;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (newRoute == null) {
      return;
    }
    if (index >= 0) {
      _stack[index] = newRoute;
    } else {
      _stack.add(newRoute);
    }
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
