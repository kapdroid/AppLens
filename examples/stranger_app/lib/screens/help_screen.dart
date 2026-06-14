import 'package:flutter/material.dart';

import 'settings_screen.dart';

/// A simple support/help screen with a link onward to settings.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const String route = '/help';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(key: const Key('app_bar'), title: const Text('Help')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('How can we help?', key: Key('lbl_help')),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('btn_open_settings'),
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
