import 'package:flutter/material.dart';

import 'profile_screen.dart';

/// The account login form — two text fields and a submit button. The button is
/// always enabled so the walk reaches the profile; the fields exist so a graph
/// can exercise enter_text.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  static const String route = '/login';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(key: const Key('app_bar'), title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const TextField(
              key: Key('field_username'),
              decoration: InputDecoration(labelText: 'Username'),
            ),
            const TextField(
              key: Key('field_password'),
              obscureText: true,
              decoration: InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('btn_login'),
              onPressed: () =>
                  Navigator.pushNamed(context, ProfileScreen.route),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
