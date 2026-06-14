import 'package:flutter/material.dart';

import '../data/catalog.dart';
import 'product_detail_screen.dart';

/// Past orders. Tapping one reorders it — a cross-module jump back into the shop
/// flow (the product detail screen).
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  static const String route = '/orders';

  @override
  Widget build(BuildContext context) {
    final past = buildCatalog().take(8).toList();
    return Scaffold(
      appBar: AppBar(key: const Key('app_bar'), title: const Text('My orders')),
      body: ListView.builder(
        key: const Key('list_orders'),
        itemCount: past.length,
        itemBuilder: (context, index) {
          final product = past[index];
          return ListTile(
            key: Key('order_${product.id}'),
            title: Text('Order #${1000 + product.id}'),
            subtitle: Text(product.name),
            trailing: const Text('Reorder'),
            onTap: () => Navigator.pushNamed(
              context,
              ProductDetailScreen.route,
              arguments: product,
            ),
          );
        },
      ),
    );
  }
}
