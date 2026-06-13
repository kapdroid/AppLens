/// A catalog item in the stranger app.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
  });

  final int id;
  final String name;
  final double price;
  final String category;
}
