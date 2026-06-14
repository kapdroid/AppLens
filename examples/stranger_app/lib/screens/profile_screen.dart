import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'orders_screen.dart';

/// The signed-in account profile: a name, a link to past orders, and sign-out.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const String route = '/profile';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(key: const Key('app_bar'), title: const Text('Profile')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Signed in as Alex', key: Key('lbl_account_name')),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('btn_view_orders'),
              onPressed: () => Navigator.pushNamed(context, OrdersScreen.route),
              child: const Text('My orders'),
            ),
            TextButton(
              key: const Key('btn_logout'),
              onPressed: () => Navigator.popUntil(
                context,
                ModalRoute.withName(HomeScreen.route),
              ),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
