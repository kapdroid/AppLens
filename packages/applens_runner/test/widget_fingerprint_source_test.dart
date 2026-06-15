import 'dart:async';

import 'package:applens_runner/applens_runner.dart';
import 'package:applens_runner/src/driver/applens_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('captures route from the observer and anchors from the tree', (
    tester,
  ) async {
    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const Scaffold(
          body: Center(child: Text('hi', key: Key('app_root'))),
        ),
      ),
    );

    final source = WidgetFingerprintSource(
      AppLensWidgetDriver(tester),
      observer,
    );
    final fingerprint = await source.capture();

    expect(fingerprint.route, '/');
    expect(fingerprint.anchors, contains('app_root'));
    expect(fingerprint.overlay, isFalse);
  });

  testWidgets('currentRoute follows the stack on push and pop, not just push', (
    tester,
  ) async {
    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      routes: {
        '/': (_) => const Scaffold(body: Text('home')),
        '/detail': (_) => const Scaffold(body: Text('detail')),
      },
    ));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    expect(observer.currentRoute, '/');
    unawaited(navigator.pushNamed('/detail')); // completes when the route pops
    await tester.pumpAndSettle();
    expect(observer.currentRoute, '/detail');
    // Popping must restore the underlying route — not leave it stale at /detail.
    navigator.pop();
    await tester.pumpAndSettle();
    expect(observer.currentRoute, '/');
  });

  testWidgets(
      'texts map carries the first Text descendant for each keyed widget', (
    tester,
  ) async {
    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: Column(children: const [
            ElevatedButton(
              key: Key('btn_start'),
              onPressed: null,
              child: Text('Start shopping'),
            ),
            Text('plain', key: Key('lbl_plain')),
          ]),
        ),
      ),
    );

    final source =
        WidgetFingerprintSource(AppLensWidgetDriver(tester), observer);
    final fingerprint = await source.capture();

    expect(fingerprint.texts['btn_start'], 'Start shopping');
    expect(fingerprint.texts['lbl_plain'], 'plain');
  });

  testWidgets('an unnamed top route reports a null route (not the stale name)',
      (
    tester,
  ) async {
    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: const Scaffold(body: Text('home')),
    ));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    expect(observer.currentRoute, '/');
    unawaited(navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('unnamed')),
    )));
    await tester.pumpAndSettle();
    expect(observer.currentRoute, isNull); // honest: unnamed, not stale '/'
  });
}
