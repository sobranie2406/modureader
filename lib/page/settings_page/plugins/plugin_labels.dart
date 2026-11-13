import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:flutter/material.dart';

/// Localised capability description shared by the install preview and the
/// plugin details page so both explain a permission the same way.
String pluginCapabilityLabel(BuildContext context, String capability) {
  switch (capability) {
    case kAiPromptPackCapability:
      return ModuStrings.text(
          context, '添加 AI 提示词模板', 'Add AI prompt templates');
    case kSelectionActionCapability:
      return ModuStrings.text(
          context, '添加划词工具栏动作', 'Add selection toolbar actions');
    case 'storage:plugin':
      return ModuStrings.text(context, '使用插件私有目录', 'Use plugin storage');
    default:
      return capability;
  }
}
