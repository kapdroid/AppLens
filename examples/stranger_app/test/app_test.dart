import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stranger_app/cart_model.dart';
import 'package:stranger_app/main.dart';

void main() {
  testWidgets('shopping flow: home → catalog → product → cart → confirm', (
    tester,
  ) async {
    await tester.pumpWidget(StrangerApp(cart: CartModel()));
    expect(find.byKey(const Key('lbl_welcome')), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn_start_shopping')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('list_catalog')), findsOneWidget);

    // Scroll the long list to a product well below the fold, then open it.
    await tester.scrollUntilVisible(
      find.byKey(const Key('product_40')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('product_40')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lbl_product_name')), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn_add_to_cart')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('list_cart_items')), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn_place_order')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lbl_order_confirmed')), findsOneWidget);
  });
}
