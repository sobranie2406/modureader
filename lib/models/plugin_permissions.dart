/// Runtime permission catalogue for plugins.
///
/// Two tiers mirror the platform permission model the user asked for:
///
/// * [PluginPermissionTier.install] — materialised when the package is
///   installed (prompts, toolbar actions, script entry points). The user sees
///   them as information, because refusing them means not installing.
/// * [PluginPermissionTier.user] — a runtime grant that starts **denied** and
///   must be switched on in the plugin details page before any host call that
///   relies on it succeeds.
///
/// Tokens must match `_capabilityPattern` (`group:action`), so a token such as
/// `clipboard` is invalid and `clipboard:write` is used instead.
library;

import 'package:modu_reader/models/plugin_manifest.dart';

/// Capability tokens live in the manifest model so a package cannot declare a
/// grant the host has no catalogue entry for.
export 'package:modu_reader/models/plugin_manifest.dart'
    show
        kAiInvokeCapability,
        kAiPromptPackCapability,
        kArticleCaptureCapability,
        kArticleExtractCapability,
        kBookActionCapability,
        kBookContentCapability,
        kClipboardReadCapability,
        kClipboardWriteCapability,
        kDictionaryLookupCapability,
        kDictionaryTransformCapability,
        kKnowledgeQueryCapability,
        kLibraryPrivateCapability,
        kLibraryPrivateControlCapability,
        kLibraryPrivatePolicyCapability,
        kLibraryReadCapability,
        kLibraryWriteCapability,
        kNoteReadCapability,
        kNoteWriteCapability,
        kPluginDeviceSettingsCapability,
        kReadingReadCapability,
        kScriptRunCapability,
        kSearchLibraryCapability,
        kSelectionActionCapability,
        kShareTextCapability,
        kTranslateInvokeCapability,
        kTtsInvokeCapability,
        kUiDialogCapability,
        kUiProgressCapability,
        kUrlOpenCapability;

enum PluginPermissionTier {
  /// Granted by installing; the details page lists it read-only.
  install,

  /// Starts denied; the user decides per plugin.
  user,
}

enum PluginPermissionGroup {
  content,
  library,
  intelligence,
  system,
  network,
  installOnly,
}

class PluginPermissionSpec {
  const PluginPermissionSpec({
    required this.token,
    required this.tier,
    required this.group,
    required this.zh,
    required this.en,
    this.danger = false,
  });

  final String token;
  final PluginPermissionTier tier;
  final PluginPermissionGroup group;
  final String zh;
  final String en;

  /// Requires an explicit confirmation before the switch flips on.
  final bool danger;

  bool get isRuntime => tier == PluginPermissionTier.user;
}

/// Every capability the manifest may declare.
///
/// Order is the order the details page renders; grouping is derived from
/// [PluginPermissionGroup] so the page never hard-codes a capability name.
const List<PluginPermissionSpec> kPluginPermissions = [
  // Content the user created by reading.
  PluginPermissionSpec(
      token: kLibraryReadCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.content,
      zh: '读取已授权书籍列表',
      en: 'Read granted books'),
  PluginPermissionSpec(
      token: kBookContentCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.content,
      zh: '读取当前书籍目录与章节正文',
      en: 'Read the current book TOC and chapter text'),
  PluginPermissionSpec(
      token: kNoteReadCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.content,
      zh: '读取划线与笔记',
      en: 'Read highlights and notes'),
  PluginPermissionSpec(
      token: kNoteWriteCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.content,
      zh: '保存笔记',
      en: 'Save notes'),
  PluginPermissionSpec(
      token: kReadingReadCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.content,
      zh: '读取阅读时长与历史',
      en: 'Read reading time and history'),
  PluginPermissionSpec(
      token: kSearchLibraryCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.content,
      zh: '搜索整个书库与笔记',
      en: 'Search the library and notes'),
  PluginPermissionSpec(
      token: kKnowledgeQueryCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.content,
      zh: '检索本地向量索引',
      en: 'Search the local vector index'),

  // Library mutations.
  PluginPermissionSpec(
      token: kLibraryWriteCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.library,
      zh: '修改标签与分组',
      en: 'Change tags and groups'),
  PluginPermissionSpec(
      token: kLibraryPrivateCapability,
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.library,
      zh: '管理私密书籍',
      en: 'Manage private books'),
  PluginPermissionSpec(
      token: kLibraryPrivateControlCapability,
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.library,
      zh: '选择书籍并设置私密状态',
      en: 'Choose books and change private status'),
  PluginPermissionSpec(
      token: kLibraryPrivatePolicyCapability,
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.library,
      zh: '判断新书是否归入私密书库',
      en: 'Decide whether imported books are private'),

  // Models the user pays for.
  PluginPermissionSpec(
      token: kAiInvokeCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.intelligence,
      zh: '使用你配置的 AI 模型',
      en: 'Use your configured AI model',
      danger: true),
  PluginPermissionSpec(
      token: kTranslateInvokeCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.intelligence,
      zh: '使用你的翻译引擎',
      en: 'Use your translation engine'),
  PluginPermissionSpec(
      token: kTtsInvokeCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.intelligence,
      zh: '使用你的朗读者',
      en: 'Use your text-to-speech voice'),
  PluginPermissionSpec(
      token: kDictionaryLookupCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.intelligence,
      zh: '查询已安装的词典',
      en: 'Query installed dictionaries'),

  // System surfaces.
  PluginPermissionSpec(
      token: kClipboardReadCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.system,
      zh: '读取剪贴板',
      en: 'Read the clipboard',
      danger: true),
  PluginPermissionSpec(
      token: kClipboardWriteCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.system,
      zh: '写入剪贴板',
      en: 'Write to the clipboard'),
  PluginPermissionSpec(
      token: kShareTextCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.system,
      zh: '调起系统分享',
      en: 'Open the system share sheet'),
  PluginPermissionSpec(
      token: kUiDialogCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.system,
      zh: '显示确认框与提示',
      en: 'Show confirmations and prompts'),
  PluginPermissionSpec(
      token: kUiProgressCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.system,
      zh: '显示任务进度',
      en: 'Show task progress'),
  PluginPermissionSpec(
      token: kUrlOpenCapability,
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.system,
      zh: '在浏览器中打开链接',
      en: 'Open links in the browser'),
  PluginPermissionSpec(
      token: kArticleCaptureCapability,
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.system,
      zh: '提取指定网页并保存',
      en: 'Extract and save a chosen web page'),
  PluginPermissionSpec(
      token: kArticleExtractCapability,
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.system,
      zh: '离线处理网页正文',
      en: 'Process article HTML offline'),
  PluginPermissionSpec(
      token: kDictionaryTransformCapability,
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.system,
      zh: '生成查词变体',
      en: 'Suggest dictionary word forms'),

  // Network and declarative installs.
  PluginPermissionSpec(
      token: 'net:http',
      tier: PluginPermissionTier.user,
      group: PluginPermissionGroup.network,
      zh: '访问声明的网站',
      en: 'Access declared websites',
      danger: true),
  PluginPermissionSpec(
      token: kScriptRunCapability,
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.installOnly,
      zh: '运行插件脚本',
      en: 'Run plugin scripts'),
  PluginPermissionSpec(
      token: kSelectionActionCapability,
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.installOnly,
      zh: '添加划词工具栏动作',
      en: 'Add selection toolbar actions'),
  PluginPermissionSpec(
      token: kBookActionCapability,
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.installOnly,
      zh: '添加书籍操作菜单',
      en: 'Add book menu actions'),
  PluginPermissionSpec(
      token: kAiPromptPackCapability,
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.installOnly,
      zh: '添加 AI 提示词模板',
      en: 'Add AI prompt templates'),
  PluginPermissionSpec(
      token: kPluginDeviceSettingsCapability,
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.installOnly,
      zh: '仅在本机保存插件设置',
      en: 'Store plugin settings on this device'),
  PluginPermissionSpec(
      token: 'storage:plugin',
      tier: PluginPermissionTier.install,
      group: PluginPermissionGroup.installOnly,
      zh: '使用插件私有目录',
      en: 'Use plugin storage'),
];

/// Capabilities that already shipped before manual grants existed.
///
/// They are grandfathered on install so upgrading the app never silently
/// breaks an installed plugin; every capability added later starts denied.
const Set<String> kLegacyRuntimeCapabilities = {
  'net:http',
  kLibraryReadCapability,
  kNoteWriteCapability,
  kLibraryPrivateCapability,
  kLibraryPrivateControlCapability,
  kLibraryPrivatePolicyCapability,
  kArticleCaptureCapability,
};

final Map<String, PluginPermissionSpec> _byToken = {
  for (final spec in kPluginPermissions) spec.token: spec,
};

PluginPermissionSpec? pluginPermissionSpec(String token) => _byToken[token];

/// Unknown tokens are treated as runtime grants so a future capability from a
/// newer package can never be used without an explicit grant.
bool isRuntimePermission(String token) =>
    _byToken[token]?.isRuntime ?? true;
