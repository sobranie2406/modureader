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
    case kBookActionCapability:
      return ModuStrings.text(context, '添加书籍操作菜单', 'Add book menu actions');
    case 'storage:plugin':
      return ModuStrings.text(context, '使用插件私有目录', 'Use plugin storage');
    case kScriptRunCapability:
      return ModuStrings.text(context, '运行插件脚本', 'Run plugin scripts');
    case 'net:http':
      return ModuStrings.text(context, '访问声明的网站', 'Access declared websites');
    case kLibraryReadCapability:
      return ModuStrings.text(context, '读取授权书籍', 'Read granted books');
    case kNoteWriteCapability:
      return ModuStrings.text(context, '保存笔记', 'Save notes');
    case kLibraryPrivateCapability:
      return ModuStrings.text(context, '管理私密书籍', 'Manage private books');
    case kLibraryPrivateControlCapability:
      return ModuStrings.text(
          context, '选择书籍并设置私密状态', 'Choose books and change private status');
    case kLibraryPrivatePolicyCapability:
      return ModuStrings.text(
          context, '判断新书是否归入私密书库', 'Decide whether imported books are private');
    case kPluginDeviceSettingsCapability:
      return ModuStrings.text(
          context, '仅在本机保存插件设置', 'Store plugin settings on this device');
    case kDictionaryTransformCapability:
      return ModuStrings.text(
          context, '生成查词变体', 'Suggest dictionary word forms');
    case kArticleCaptureCapability:
      return ModuStrings.text(
          context, '提取指定网页并保存', 'Extract and save a chosen web page');
    case kArticleExtractCapability:
      return ModuStrings.text(
          context, '离线处理网页正文', 'Process article HTML offline');
    default:
      return capability;
  }
}
