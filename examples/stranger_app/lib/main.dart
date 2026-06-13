import 'package:flutter/material.dart';

import 'cart_model.dart';
import 'models/product.dart';
import 'screens/cart_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/home_screen.dart';
import 'screens/order_confirm_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(StrangerApp(cart: CartModel()));
}

/// The stranger app root. The cart is injected so tests (and, later, AppLens
/// seed hooks) can start from a known state.
class StrangerApp extends StatelessWidget {
  const StrangerApp(
      {super.key, required this.cart, this.navigatorObservers = const []});

  final CartModel cart;
  final List<NavigatorObserver> navigatorObservers;

  @override
  Widget build(BuildContext context) {
    return CartScope(
      cart: cart,
      child: MaterialApp(
        navigatorObservers: navigatorObservers,
        title: 'Stranger Shop',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        initialRoute: HomeScreen.route,
        routes: {
          HomeScreen.route: (_) => const HomeScreen(),
          CatalogScreen.route: (_) => const CatalogScreen(),
          CartScreen.route: (_) => const CartScreen(),
          OrderConfirmScreen.route: (_) => const OrderConfirmScreen(),
          SettingsScreen.route: (_) => const SettingsScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == ProductDetailScreen.route) {
            final product = settings.arguments! as Product;
            return MaterialPageRoute<void>(
              builder: (_) => ProductDetailScreen(product: product),
            );
          }
          return null;
        },
      ),
    );
  }
}
