import 'package:flutter/material.dart';

import '../data/catalog.dart';
import 'product_detail_screen.dart';

/// A long, scrollable catalog — the deliberate scroll-into-long-list surface
/// the walking skeleton exercises.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  static const String route = '/catalog';

  @override
  Widget build(BuildContext context) {
    final catalog = buildCatalog();
    return Scaffold(
      appBar: AppBar(key: const Key('app_bar'), title: const Text('Catalog')),
      body: ListView.builder(
        key: const Key('list_catalog'),
        itemCount: catalog.length,
        itemBuilder: (context, index) {
          final product = catalog[index];
          return ListTile(
            key: Key('product_${product.id}'),
            title: Text(product.name),
            subtitle: Text(product.category),
            trailing: Text('\$${product.price.toStringAsFixed(2)}'),
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
