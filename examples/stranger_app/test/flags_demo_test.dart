// Proves the tier-1 flag + guard machinery end-to-end on the real app: the live
// fingerprint carries flags from both tiers (UI-inferred cart_count, SDK-recorded
// journey.started), flag-based identity disambiguates two same-route states, and
// the guard precondition is evaluated. Runs headless in the gate and on a device
// with `-d <emulator>`.
import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:applens_runner/src/driver/applens_driver.dart';
import 'package:applens_runner/src/run/node_matcher.dart';
import 'package:applens_runner/src/run/tier1.dart';
import 'package:applens_sdk/applens_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stranger_app/cart_model.dart';
import 'package:stranger_app/main.dart';

void main() {
  testWidgets('flags + guards drive identity on the real app', (tester) async {
    AppLensState.reset();
    addTearDown(AppLensState.reset);

    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(
        StrangerApp(cart: CartModel(), navigatorObservers: [observer]));
    await tester.pumpAndSettle();

    final driver = AppLensWidgetDriver(tester);
    // Composite source: cart_count inferred from the UI (Tier-0, zero access),
    // journey.started read from the app's applens_sdk state (Tier-1).
    final fingerprints = WidgetFingerprintSource(
      driver,
      observer,
      flags: CompositeFlagSource([
        const UiInferenceFlagSource([CountProbe('cart_count', 'cart_item_')]),
        CallbackFlagSource(() => AppLensState.flags),
      ]),
    );

    // A Tier-1 app records journey state via applens_sdk when shopping starts;
    // the stranger app stays zero-access, so the test stands in for that hook.
    AppLensState.setFlag('journey.started', true);

    await driver.tap(const KeySelector('btn_start_shopping'));
    await driver.settle(const SettlePolicy());
    await driver.tap(const KeySelector('product_0'));
    await driver.settle(const SettlePolicy());
    await driver.tap(const KeySelector('btn_add_to_cart'));
    await driver.settle(const SettlePolicy());

    final fp = await fingerprints.capture();
    expect(fp.route, '/cart');
    expect(fp.flags['cart_count'], '1',
        reason: 'UI-inferred from one cart_item_');
    expect(fp.flags['journey.started'], 'true', reason: 'SDK-recorded');

    // Flag-based identity: the filled-cart state matches, an empty-cart state
    // (same route) does not — the disambiguation flags exist to make.
    final filled = NodeIdentity(
        route: '/cart', flags: {'cart_count': FlagConstraint.parse('>0')});
    final empty = NodeIdentity(
        route: '/cart', flags: {'cart_count': FlagConstraint.parse('0')});
    expect(identityMatches(filled, fp), isTrue);
    expect(identityMatches(empty, fp), isFalse);

    // Guard: journey.started satisfies the cart's precondition; clearing it fails.
    final cart = parseNode(
      'identity:\n  route: /cart\n'
      'payload:\n  guards: { requires: [journey.started] }\n',
      source: 'cart.yaml',
      assignedId: 'cart',
    );
    expect(evaluateGuard(cart, fp)!.passed, isTrue);

    AppLensState.clearFlag('journey.started');
    final after = await fingerprints.capture();
    expect(evaluateGuard(cart, after)!.passed, isFalse,
        reason: 'precondition no longer holds');
  });
}
