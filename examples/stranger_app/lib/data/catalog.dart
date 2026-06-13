import '../models/product.dart';

const List<String> _nouns = [
  'Lamp',
  'Mug',
  'Notebook',
  'Backpack',
  'Bottle',
  'Headphones',
  'Keyboard',
  'Plant',
  'Candle',
  'Blanket',
];

const List<String> _categories = ['Home', 'Office', 'Outdoors', 'Kitchen'];

/// Builds a deterministic catalog of 60 products. Deterministic by design — the
/// same input always yields the same list, which AppLens's deterministic core
/// relies on.
List<Product> buildCatalog() {
  final products = <Product>[];
  for (var i = 0; i < 60; i++) {
    products.add(
      Product(
        id: i,
        name: '${_nouns[i % _nouns.length]} #$i',
        price: 4.0 + (i % 20) * 1.5,
        category: _categories[i % _categories.length],
      ),
    );
  }
  return products;
}
