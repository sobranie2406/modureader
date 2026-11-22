import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/plugin_permissions.dart';
import 'package:flutter/material.dart';

/// Localised capability description shared by the install preview and the
/// plugin details page so both explain a permission the same way.
///
/// The copy lives in the permission catalogue so a new capability needs one
/// entry, not a second switch statement here.
String pluginCapabilityLabel(BuildContext context, String capability) {
  final spec = pluginPermissionSpec(capability);
  if (spec != null) return ModuStrings.text(context, spec.zh, spec.en);
  switch (capability) {
    case 'storage:plugin':
      return ModuStrings.text(context, '使用插件私有目录', 'Use plugin storage');
    default:
      return capability;
  }
}

/// Group heading for the runtime permission section.
String pluginPermissionGroupLabel(
    BuildContext context, PluginPermissionGroup group) {
  final (zh, en) = switch (group) {
    PluginPermissionGroup.content => ('阅读内容', 'Reading content'),
    PluginPermissionGroup.library => ('书库', 'Library'),
    PluginPermissionGroup.intelligence => ('模型与词典', 'Models and dictionaries'),
    PluginPermissionGroup.system => ('系统功能', 'System'),
    PluginPermissionGroup.network => ('网络', 'Network'),
    PluginPermissionGroup.installOnly => ('随安装授予', 'Granted by installing'),
  };
  return ModuStrings.text(context, zh, en);
}
