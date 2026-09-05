import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:flutter/material.dart';

class DeveloperOptionsPage extends StatelessWidget {
  const DeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Options'),
      ),
      body: AnimatedBuilder(
        animation: Prefs(),
        builder: (context, _) {
          final enabled = Prefs().developerOptionsEnabled;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              SwitchListTile(
                title: const Text('Enable Developer Options'),
                subtitle: const Text(
                    'Toggle off to hide developer entries in settings'),
                value: enabled,
                onChanged: (value) {
                  Prefs().developerOptionsEnabled = value;
                  if (!value && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
