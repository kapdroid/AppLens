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
}
