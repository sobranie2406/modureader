import 'package:flutter/material.dart';
import 'package:modu_reader/page/settings_page/plugins/plugins_page.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';

/// Retains the old route name while opening plugin management directly.
class ExperimentalSettings extends StatelessWidget {
  const ExperimentalSettings({super.key, this.host});
  final PluginHost? host;

  @override
  Widget build(BuildContext context) => PluginSettings(host: host);
}
