import 'package:flutter/material.dart';

import 'cart_screen.dart';
import 'catalog_screen.dart';
import 'help_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

/// Entry screen with navigation into the shopping flow.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const String route = '/';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(key: const Key('app_bar'), title: const Text('Stranger Shop')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Welcome', key: Key('lbl_welcome')),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('btn_start_shopping'),
              onPressed: () =>
                  Navigator.pushNamed(context, CatalogScreen.route),
              child: const Text('Start shopping'),
            ),
            ElevatedButton(
              key: const Key('btn_view_cart'),
              onPressed: () => Navigator.pushNamed(context, CartScreen.route),
              child: const Text('View cart'),
            ),
            ElevatedButton(
              key: const Key('btn_account'),
              onPressed: () => Navigator.pushNamed(context, LoginScreen.route),
              child: const Text('Account'),
            ),
            TextButton(
              key: const Key('btn_help'),
              onPressed: () => Navigator.pushNamed(context, HelpScreen.route),
              child: const Text('Help'),
            ),
            TextButton(
              key: const Key('btn_settings'),
              onPressed: () =>
                  Navigator.pushNamed(context, SettingsScreen.route),
              child: const Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
