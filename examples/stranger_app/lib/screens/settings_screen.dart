import 'package:flutter/material.dart';

/// A simple settings screen with one stateful toggle.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const String route = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SwitchListTile(
        key: const Key('switch_dark_mode'),
        title: const Text('Dark mode'),
        value: _darkMode,
        onChanged: (value) => setState(() => _darkMode = value),
      ),
    );
  }
}
