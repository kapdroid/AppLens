import 'package:applens_runner/applens_runner.dart';
import 'package:applens_runner/src/driver/applens_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(Widget child) => MaterialApp(home: Scaffold(body: child));

List<String> _keysOf(SerializedWidget node) => [
      if (node.key != null) node.key!,
      for (final child in node.children) ..._keysOf(child),
    ];

bool _anyHasRect(SerializedWidget node) =>
    node.rect != null || node.children.any(_anyHasRect);

void main() {
  testWidgets('tap invokes the keyed widget', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _harness(
        Center(
          child: ElevatedButton(
            key: const Key('go'),
            onPressed: () => tapped = true,
            child: const Text('Go'),
          ),
        ),
      ),
    );
    final driver = AppLensWidgetDriver(tester);

    await driver.tap(const KeySelector('go'));
    await driver.settle(const SettlePolicy());

    expect(tapped, isTrue);
  });

  testWidgets('enterText drives the field through the IME', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _harness(
        Center(
          child: SizedBox(
            width: 200,
            child: TextField(key: const Key('field'), controller: controller),
          ),
        ),
      ),
    );
    final driver = AppLensWidgetDriver(tester);

    await driver.enterText(const KeySelector('field'), 'hello world');

    expect(controller.text, 'hello world');
  });

  testWidgets('scrollTo reveals an item deep in a long list, then tap works', (
    tester,
  ) async {
    var tappedIndex = -1;
    await tester.pumpWidget(
      _harness(
        ListView.builder(
          itemCount: 200,
          itemBuilder: (_, index) => ListTile(
            key: Key('row_$index'),
            title: Text('Row $index'),
            onTap: () => tappedIndex = index,
          ),
        ),
      ),
    );
    final driver = AppLensWidgetDriver(tester);

    await driver.scrollTo(const KeySelector('row_150'));
    await driver.tap(const KeySelector('row_150'));
    await driver.settle(const SettlePolicy());

    expect(tappedIndex, 150);
  });

  testWidgets('tapping an obscured widget fails, naming the obscurer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        Stack(
          children: [
            Center(
              child: ElevatedButton(
                key: const Key('under'),
                onPressed: () {},
                child: const Text('Under'),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                onTap: () {},
                child: Container(color: const Color(0x80000000)),
              ),
            ),
          ],
        ),
      ),
    );
    final driver = AppLensWidgetDriver(tester);

    await expectLater(
      driver.tap(const KeySelector('under')),
      throwsA(
        isA<DriverException>().having(
          (e) => e.message,
          'message',
          contains('obscured by'),
        ),
      ),
    );
  });

  testWidgets('tree() serializes keyed widgets', (tester) async {
    await tester.pumpWidget(
      _harness(const Center(child: Text('hi', key: Key('lbl')))),
    );
    final driver = AppLensWidgetDriver(tester);

    final snapshot = await driver.tree();

    expect(_keysOf(snapshot.root), contains('lbl'));
    // Box-backed nodes carry painted geometry — the tier-2 layout hash needs it.
    expect(_anyHasRect(snapshot.root), isTrue);
  });

  testWidgets('a missing selector throws', (tester) async {
    await tester.pumpWidget(_harness(const SizedBox()));
    final driver = AppLensWidgetDriver(tester);

    await expectLater(
      driver.tap(const KeySelector('nope')),
      throwsA(isA<DriverException>()),
    );
  });
}
