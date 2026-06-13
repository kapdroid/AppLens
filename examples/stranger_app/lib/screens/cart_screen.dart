import 'package:flutter/material.dart';

import '../cart_model.dart';
import 'order_confirm_screen.dart';

/// The cart with its line items, total, and the place-order action.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  static const String route = '/cart';

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: cart.items.isEmpty
          ? const Center(
              child: Text('Your cart is empty', key: Key('lbl_empty_cart')),
            )
          : ListView.builder(
              key: const Key('list_cart_items'),
              itemCount: cart.items.length,
              itemBuilder: (context, index) {
                final product = cart.items[index];
                return ListTile(
                  key: Key('cart_item_${product.id}'),
                  title: Text(product.name),
                  trailing: Text('\$${product.price.toStringAsFixed(2)}'),
                );
              },
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(
              'Total: \$${cart.total.toStringAsFixed(2)}',
              key: const Key('lbl_total'),
            ),
            const Spacer(),
            ElevatedButton(
              key: const Key('btn_place_order'),
              onPressed: cart.items.isEmpty
                  ? null
                  : () {
                      cart.clear();
                      Navigator.pushNamed(context, OrderConfirmScreen.route);
                    },
              child: const Text('Place order'),
            ),
          ],
        ),
      ),
    );
  }
}
