import 'package:applens_runner/applens_runner.dart';
import 'package:applens_runner/src/driver/fake_driver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records actions in order', () async {
    final driver = FakeDriver();
    await driver.tap(const KeySelector('btn'));
    await driver.enterText(const KeySelector('field'), 'hello');
    await driver.scrollTo(const KeySelector('item'));
    await driver.back();
    await driver.settle(const SettlePolicy());

    expect(driver.actionLog, [
      'tap key "btn"',
      'enterText key "field" "hello"',
      'scrollTo key "item"',
      'back',
      'settle',
    ]);
  });

  test('returns recorded tree snapshots in order, clamping at the last',
      () async {
    final driver = FakeDriver(
      trees: const [
        WidgetTreeSnapshot(SerializedWidget(type: 'A')),
        WidgetTreeSnapshot(SerializedWidget(type: 'B')),
      ],
    );

    expect((await driver.tree()).root.type, 'A');
    expect((await driver.tree()).root.type, 'B');
    expect((await driver.tree()).root.type, 'B');
  });

  test('native() is unsupported by the fake', () async {
    await expectLater(
      FakeDriver().native(const PermissionAction('camera')),
      throwsA(isA<DriverException>()),
    );
  });
}
