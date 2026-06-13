import 'package:flutter/widgets.dart';

import 'models/product.dart';

/// A tiny in-memory cart. A [ChangeNotifier] so [CartScope] can rebuild
/// dependents when it changes.
class CartModel extends ChangeNotifier {
  final List<Product> _items = [];

  List<Product> get items => List<Product>.unmodifiable(_items);

  int get count => _items.length;

  double get total =>
      _items.fold<double>(0, (sum, product) => sum + product.price);

  void add(Product product) {
    _items.add(product);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

/// Exposes the [CartModel] to the widget tree and rebuilds dependents on change.
class CartScope extends InheritedNotifier<CartModel> {
  const CartScope({super.key, required CartModel cart, required super.child})
      : super(notifier: cart);

  static CartModel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CartScope>();
    return scope!.notifier!;
  }
}
