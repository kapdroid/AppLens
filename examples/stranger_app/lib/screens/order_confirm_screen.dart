import 'package:flutter/material.dart';

import 'home_screen.dart';

/// Confirms a placed order and returns home.
class OrderConfirmScreen extends StatelessWidget {
  const OrderConfirmScreen({super.key});

  static const String route = '/confirm';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            const Text('Order confirmed!', key: Key('lbl_order_confirmed')),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('btn_back_home'),
              onPressed: () => Navigator.popUntil(
                context,
                ModalRoute.withName(HomeScreen.route),
              ),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }
}
