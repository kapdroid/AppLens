import 'package:applens_core/applens_core.dart' show SwipeDirection;
import 'package:applens_runner/applens_runner.dart';
import 'package:applens_runner/src/driver/applens_driver.dart';
import 'package:applens_runner/src/driver/fake_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('openDeepLink', () {
    testWidgets('routes a named deep link through the app in-process',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        initialRoute: '/',
        routes: {
          '/': (_) => const Scaffold(body: Text('home', key: Key('home'))),
          '/detail': (_) =>
              const Scaffold(body: Text('detail', key: Key('detail'))),
        },
      ));
      final driver = AppLensWidgetDriver(tester);
      expect(find.byKey(const Key('home')), findsOneWidget);

      await driver.openDeepLink(Uri.parse('/detail'));

      expect(find.byKey(const Key('detail')), findsOneWidget,
          reason: 'the deep link pushed the /detail route');
    });

    testWidgets('an unhandled deep link is a DriverException, not a crash',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: (s) => s.name == '/'
            ? MaterialPageRoute<void>(builder: (_) => const SizedBox())
            : null, // any other route is unhandled
      ));
      final driver = AppLensWidgetDriver(tester);
      await expectLater(
        driver.openDeepLink(Uri.parse('/nope')),
        throwsA(isA<DriverException>()),
      );
    });
  });

  group('swipe', () {
    testWidgets('drags a PageView to the next page (screen-centred)',
        (tester) async {
      final controller = PageController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PageView(
            controller: controller,
            children: const [
              Center(child: Text('one', key: Key('page_0'))),
              Center(child: Text('two', key: Key('page_1'))),
            ],
          ),
        ),
      ));
      final driver = AppLensWidgetDriver(tester);
      expect(find.byKey(const Key('page_0')), findsOneWidget);

      await driver.swipe(SwipeDirection.left);

      expect(controller.page?.round(), 1,
          reason: 'advanced to the second page');
    });

    testWidgets('swipe on: an off-screen widget is refused, not a silent no-op',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            Positioned(
                left: 2000,
                top: 10,
                child: SizedBox(key: Key('off'), width: 20, height: 20)),
          ]),
        ),
      ));
      final driver = AppLensWidgetDriver(tester);
      await expectLater(
        driver.swipe(SwipeDirection.left, on: const KeySelector('off')),
        throwsA(isA<DriverException>()),
      );
    });
  });

  group('FakeDriver', () {
    test('logs the swipe direction and optional target', () async {
      final fake = FakeDriver();
      await fake.swipe(SwipeDirection.up);
      await fake.swipe(SwipeDirection.right, on: const KeySelector('card'));
      expect(fake.actionLog, ['swipe up', 'swipe right on key "card"']);
    });
  });
}
