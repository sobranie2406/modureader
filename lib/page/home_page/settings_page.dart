import 'package:anx_reader/page/settings_page/more_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/widgets/home_navigation_metrics.dart';

/// The home navigation's Settings tab opens the complete settings interface
/// directly. The optional controller is kept for compatibility with the home
/// page's compact navigation layout.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.controller, this.bottomContentInset = 0});

  final ScrollController? controller;
  final double bottomContentInset;

  @override
  Widget build(BuildContext context) {
    return SubMoreSettings(
      embedded: true,
      controller: controller,
      bottomContentInset:
          bottomContentInset + HomeNavigationClearance.of(context),
    );
  }
}
