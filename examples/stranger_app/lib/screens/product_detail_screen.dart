import 'package:flutter/material.dart';

import '../cart_model.dart';
import '../models/product.dart';
import 'cart_screen.dart';

/// Shows one product and adds it to the cart.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.product});

  static const String route = '/product';

  final Product product;

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);
    return Scaffold(
      appBar: AppBar(key: const Key('app_bar'), title: const Text('Product')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.name,
              key: const Key('lbl_product_name'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(product.category),
            const SizedBox(height: 8),
            Text('\$${product.price.toStringAsFixed(2)}'),
            const Spacer(),
            ElevatedButton(
              key: const Key('btn_add_to_cart'),
              onPressed: () {
                cart.add(product);
                Navigator.pushNamed(context, CartScreen.route);
              },
              child: const Text('Add to cart'),
            ),
          ],
        ),
      ),
    );
  }
}
