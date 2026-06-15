import 'package:applens_runner/src/run/nav_stack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavStack', () {
    test('push grows the stack; current is the top', () {
      final nav = NavStack('dashboard')
        ..push('catalog')
        ..push('product');
      expect(nav.current, 'product');
      expect(nav.depth, 3);
    });

    test('predecessor is where back lands, without mutating', () {
      final nav = NavStack('dashboard')..push('catalog');
      expect(nav.predecessor, 'dashboard');
      expect(nav.depth, 2, reason: 'predecessor is a peek, not a pop');
    });

    test('pop returns the new top and shrinks the stack', () {
      final nav = NavStack('dashboard')
        ..push('catalog')
        ..push('product');
      expect(nav.pop(), 'catalog');
      expect(nav.current, 'catalog');
      expect(nav.depth, 2);
    });

    test('at the root, predecessor and pop stay on the entry (no-op back)', () {
      final nav = NavStack('dashboard');
      expect(nav.predecessor, 'dashboard');
      expect(nav.pop(), 'dashboard');
      expect(nav.depth, 1);
    });

    test('reset restarts at a fresh entry', () {
      final nav = NavStack('dashboard')
        ..push('catalog')
        ..reset('login');
      expect(nav.current, 'login');
      expect(nav.depth, 1);
    });

    test('path-relative back: same node, different predecessor by route taken',
        () {
      // Reaching cart via product → back lands on product.
      final viaProduct = NavStack('dashboard')
        ..push('catalog')
        ..push('product')
        ..push('cart');
      expect(viaProduct.predecessor, 'product');
      // Reaching cart via the dashboard shortcut → back lands on dashboard.
      final viaDashboard = NavStack('dashboard')..push('cart');
      expect(viaDashboard.predecessor, 'dashboard');
    });
  });
}
