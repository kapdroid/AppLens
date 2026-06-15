import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:applens_runner/src/driver/applens_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WidgetTreeSnapshot _tree(List<String> keys) => WidgetTreeSnapshot(
      SerializedWidget(
        type: 'View',
        rect: const Rect.fromLTWH(0, 0, 100, 100),
        children: [
          for (final k in keys) SerializedWidget(type: 'W', key: k),
        ],
      ),
    );

void main() {
  group('UI-inference probes', () {
    test('CountProbe counts keys by prefix → integer flag value', () {
      final src =
          const UiInferenceFlagSource([CountProbe('cart_count', 'cart_item_')]);
      expect(
          src.read(
              _tree(['cart_item_1', 'cart_item_2', 'btn_pay']))['cart_count'],
          '2');
      expect(src.read(_tree(['lbl_empty_cart']))['cart_count'], '0');
    });

    test('PresenceProbe → true/false on key presence', () {
      final src = const UiInferenceFlagSource(
          [PresenceProbe('empty', 'lbl_empty_cart')]);
      expect(src.read(_tree(['lbl_empty_cart']))['empty'], 'true');
      expect(src.read(_tree(['list_cart_items']))['empty'], 'false');
    });

    test('the inferred count satisfies the node FlagConstraint it feeds', () {
      // cart_count ">0" must accept "2" and reject "0" — the loop the matcher runs.
      final positive = FlagConstraint.parse('>0');
      final src =
          const UiInferenceFlagSource([CountProbe('cart_count', 'cart_item_')]);
      expect(positive.accepts(src.read(_tree(['cart_item_1']))['cart_count']!),
          isTrue);
      expect(positive.accepts(src.read(_tree([]))['cart_count']!), isFalse);
    });
  });

  group('CallbackFlagSource (SDK bridge)', () {
    test('reads whatever the callback returns', () {
      var state = <String, String>{'journey.started': 'true'};
      final src = CallbackFlagSource(() => state);
      expect(src.read(_tree([]))['journey.started'], 'true');
      state = {'journey.started': 'false'};
      expect(src.read(_tree([]))['journey.started'], 'false');
    });
  });

  group('CompositeFlagSource', () {
    test('merges sources; later wins on conflict (SDK over inferred)', () {
      final composite = CompositeFlagSource([
        const UiInferenceFlagSource([CountProbe('cart_count', 'cart_item_')]),
        CallbackFlagSource(
            () => {'journey.started': 'true', 'cart_count': '99'}),
      ]);
      final flags = composite.read(_tree(['cart_item_1']));
      expect(flags['journey.started'], 'true');
      expect(flags['cart_count'], '99'); // SDK (later) overrides inferred "1"
    });
  });

  testWidgets('WidgetFingerprintSource populates flags from its FlagSource',
      (tester) async {
    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const Scaffold(
          body: Column(children: [
            SizedBox(key: Key('cart_item_1')),
            SizedBox(key: Key('cart_item_2')),
          ]),
        ),
      ),
    );
    final source = WidgetFingerprintSource(
      AppLensWidgetDriver(tester),
      observer,
      flags:
          const UiInferenceFlagSource([CountProbe('cart_count', 'cart_item_')]),
    );
    final fp = await source.capture();
    expect(fp.flags['cart_count'], '2');
  });

  testWidgets('default source reads no flags (route+anchor identity preserved)',
      (tester) async {
    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: const Scaffold(body: SizedBox(key: Key('x'))),
    ));
    final fp =
        await WidgetFingerprintSource(AppLensWidgetDriver(tester), observer)
            .capture();
    expect(fp.flags, isEmpty);
  });
}
