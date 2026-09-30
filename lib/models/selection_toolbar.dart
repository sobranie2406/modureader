import 'dart:convert';
import 'dart:ui';
import 'package:anx_reader/l10n/modu_strings.dart';

import 'package:anx_reader/constants/note_annotations.dart';

/// Stable action IDs, rather than translated labels or platform icon codes.
class SelectionToolbarItem {
  const SelectionToolbarItem(this.id, this.action,
      {this.enabled = true,
      this.name = '',
      this.icon = '',
      this.prompt = '',
      this.skillId = 'selection_toolbar'});

  final String id, action, name, icon, prompt, skillId;
  final bool enabled;
  bool get isCustom => action == 'aiCommand';
  bool get isAi => action == 'ai' || isCustom;

  SelectionToolbarItem copyWith(
          {bool? enabled,
          String? name,
          String? icon,
          String? prompt,
          String? skillId}) =>
      SelectionToolbarItem(id, action,
          enabled: enabled ?? this.enabled,
          name: name ?? this.name,
          icon: icon ?? this.icon,
          prompt: prompt ?? this.prompt,
          skillId: skillId ?? this.skillId);

  String localizedName(Locale locale) => _isDefaultName
      ? ModuStrings.value(locale, 'selection_${id}_name', name)
      : name;
  String localizedPrompt(Locale locale) => _isDefaultPrompt
      ? ModuStrings.value(locale, 'selection_${id}_prompt', prompt)
      : prompt;
  bool get _isDefaultName =>
      _defaultItem != null &&
      ModuStrings.isDefault('selection_${id}_name', name, _defaultItem!.name);
  bool get _isDefaultPrompt =>
      _defaultItem != null &&
      ModuStrings.isDefault(
          'selection_${id}_prompt', prompt, _defaultItem!.prompt);

  String promptForSelection(String selection, {Locale? locale}) =>
      (locale == null ? prompt : localizedPrompt(locale)).replaceAllMapped(
          RegExp(r'\{\{selection\}\}|\{selection\}'),
          (_) => jsonEncode(selection));

  SelectionToolbarItem? get _defaultItem {
    for (final item in [
      ...SelectionToolbarConfig.initialItems,
      ...SelectionToolbarConfig.defaultAnnotations
    ]) {
      if (item.id == id && item.action == action) return item;
    }
    return null;
  }

  // Do not duplicate bundled template prompts in every backup/QR payload.
  // Explicit overrides still travel with the item, including an empty prompt.
  Map<String, Object> toJson() => {
        'id': id,
        'action': action,
        if (enabled != (_defaultItem?.enabled ?? true)) 'enabled': enabled,
        if (!_isDefaultName && name != (_defaultItem?.name ?? '')) 'name': name,
        if (icon != (_defaultItem?.icon ?? '')) 'icon': icon,
        if (!_isDefaultPrompt && prompt != (_defaultItem?.prompt ?? ''))
          'prompt': prompt,
        if (skillId != (_defaultItem?.skillId ?? 'selection_toolbar'))
          'skillId': skillId,
      };

  static SelectionToolbarItem fromJson(dynamic raw) {
    if (raw is! Map ||
        raw['id'] is! String ||
        raw['action'] is! String ||
        (raw.containsKey('enabled') && raw['enabled'] is! bool) ||
        ['name', 'icon', 'prompt', 'skillId']
            .any((key) => raw.containsKey(key) && raw[key] is! String)) {
      throw const FormatException('Invalid toolbar item');
    }
    final defaults =
        SelectionToolbarItem(raw['id'], raw['action'])._defaultItem;
    return SelectionToolbarItem(raw['id'], raw['action'],
        enabled: raw['enabled'] ?? defaults?.enabled ?? true,
        name: raw['name'] ?? defaults?.name ?? '',
        icon: raw['icon'] ?? defaults?.icon ?? '',
        prompt: raw['prompt'] ?? defaults?.prompt ?? '',
        skillId: raw['skillId'] ?? defaults?.skillId ?? 'selection_toolbar');
  }
}

class SelectionToolbarConfig {
  const SelectionToolbarConfig(
      {this.enabled = true,
      this.visibleCount = 5,
      this.items = initialItems,
      this.annotations = defaultAnnotations,
      this.colors = notesColors});

  static const defaultItems = [
    SelectionToolbarItem('copy', 'copy'),
    SelectionToolbarItem('search', 'search'),
    SelectionToolbarItem('translate', 'translate'),
    SelectionToolbarItem('dictionary', 'dictionary'),
    SelectionToolbarItem('narrate', 'narrate'),
    SelectionToolbarItem('note', 'note'),
    SelectionToolbarItem('ai', 'ai'),
    SelectionToolbarItem('share', 'share'),
  ];
  static const defaultAnnotations = [
    SelectionToolbarItem('delete', 'delete'),
    SelectionToolbarItem('highlight', 'highlight'),
    SelectionToolbarItem('underline', 'underline'),
    SelectionToolbarItem('colors', 'colors'),
  ];
  static const templateItems = [
    SelectionToolbarItem('custom-preset-dictionary', 'aiCommand',
        enabled: false,
        name: 'AI 词典',
        icon: 'dictionary',
        skillId: 'ai_dictionary',
        prompt:
            '解释所选词语 {selection}。英文给出 IPA 音标、词性、中文翻译、中英文释义、例句与常用搭配；中文给出带声调的拼音、含义、用法和相关词语。优先用模型已有知识，不足时根据应用返回的词典／百科资料整理并注明来源。不使用本书知识库，不编造读音或词源。'),
    SelectionToolbarItem('custom-preset-explain', 'aiCommand',
        enabled: false,
        name: '通俗解释',
        icon: 'lightbulb',
        prompt:
            '请通俗解释选中的文字 {selection}，先说明含义，再解释关键概念，必要时给一个简短例子。只围绕选中文字，不补写书中的情节或上下文。'),
    SelectionToolbarItem('custom-preset-translate', 'aiCommand',
        enabled: false,
        name: 'AI 翻译',
        icon: 'translate',
        prompt:
            '翻译选中文字 {selection}：英文译成自然的中文，中文译成自然的英文；混合文本按主要语言处理。保持原意和段落，先给译文，必要时补充易误解的词语。'),
    SelectionToolbarItem('custom-preset-polish', 'aiCommand',
        enabled: false,
        name: '润色',
        icon: 'note',
        prompt:
            '润色选中的文字 {selection}，让表达自然、清晰、流畅，保留原意、事实与语气，不增加信息。先给润色结果，再简短说明主要改动。'),
    SelectionToolbarItem('custom-preset-summary', 'aiCommand',
        enabled: false,
        name: '摘要',
        icon: 'summary',
        prompt:
            '用简洁语言概括选中的文字 {selection}，保留核心观点、关键事实和因果关系。不引用其他段落，不添加原文没有的信息。'),
    SelectionToolbarItem('custom-preset-points', 'aiCommand',
        enabled: false,
        name: '提炼要点',
        icon: 'quote',
        prompt:
            '从选中的文字 {selection} 中提炼关键要点，用简短列表呈现；有论证时区分观点和依据，有事件时区分人物、事件和结果。要点数量按原文决定，不凑数。'),
  ];
  static const initialItems = [...defaultItems, ...templateItems];
  static const iconIds = {
    'copy',
    'search',
    'translate',
    'dictionary',
    'narrate',
    'note',
    'ai',
    'share',
    'delete',
    'highlight',
    'underline',
    'colors',
    'star',
    'heart',
    'lightbulb',
    'summary',
    'quote',
    'mindmap'
  };
  static const skillIds = {
    'selection_toolbar',
    'ai_dictionary',
    'concept_explainer',
    'smart_translator',
    'vocabulary_helper',
    'mindmap'
  };

  final bool enabled;
  final int visibleCount;
  final List<SelectionToolbarItem> items, annotations;
  final List<String> colors;

  SelectionToolbarConfig copyWith(
          {bool? enabled,
          int? visibleCount,
          List<SelectionToolbarItem>? items,
          List<SelectionToolbarItem>? annotations,
          List<String>? colors}) =>
      SelectionToolbarConfig(
          enabled: enabled ?? this.enabled,
          visibleCount: visibleCount ?? this.visibleCount,
          items: items ?? this.items,
          annotations: annotations ?? this.annotations,
          colors: colors ?? this.colors);

  SelectionToolbarConfig restoreDefaults() => SelectionToolbarConfig(items: [
        ...initialItems,
        ...items.where((item) =>
            item.isCustom &&
            !templateItems.any((template) => template.id == item.id))
      ]);

  List<SelectionToolbarItem> availableItems(
          {bool footnote = false, bool aiEnabled = true}) =>
      enabled
          ? items
              .where((item) =>
                  item.enabled &&
                  (!footnote || item.action != 'note') &&
                  (aiEnabled || !item.isAi))
              .toList()
          : [];

  void validate() {
    if (visibleCount < 1 ||
        visibleCount > 8 ||
        items.length > 38 ||
        items
                .where((i) =>
                    i.isCustom && !templateItems.any((p) => p.id == i.id))
                .length >
            24 ||
        annotations.length != defaultAnnotations.length ||
        colors.isEmpty ||
        colors.length > 20 ||
        colors.map((c) => c.toUpperCase()).toSet().length != colors.length ||
        colors.any((color) => !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(color))) {
      throw const FormatException('Invalid toolbar configuration');
    }
    final ids = <String>{};
    void validateItem(
        SelectionToolbarItem item, List<SelectionToolbarItem> defaults) {
      if (!ids.add(item.id) ||
          item.id.length > 100 ||
          item.name.length > 30 ||
          item.prompt.length > 8000 ||
          !skillIds.contains(item.skillId) ||
          (item.icon.isNotEmpty && !iconIds.contains(item.icon))) {
        throw const FormatException('Invalid toolbar item');
      }
      if (item.isCustom) {
        if (!identical(defaults, defaultItems) ||
            !item.id.startsWith('custom-') ||
            item.id.length <= 7 ||
            item.name.trim().isEmpty ||
            item.prompt.trim().isEmpty) {
          throw const FormatException('Invalid custom AI command');
        }
      } else if (!defaults
              .any((d) => d.id == item.id && d.action == item.action) ||
          (!item.isAi && item.prompt.isNotEmpty)) {
        throw const FormatException('Invalid built-in toolbar action');
      }
    }

    for (final item in items) {
      validateItem(item, defaultItems);
    }
    for (final item in annotations) {
      validateItem(item, defaultAnnotations);
    }
    if (!defaultItems.every((item) => ids.contains(item.id))) {
      throw const FormatException('Missing built-in toolbar actions');
    }
  }

  String encode() {
    validate();
    return jsonEncode({
      'version': 1,
      'enabled': enabled,
      'visibleCount': visibleCount,
      'items': items.map((i) => i.toJson()).toList(),
      'annotations': annotations.map((i) => i.toJson()).toList(),
      'colors': colors
    });
  }

  static SelectionToolbarConfig decode(String value) {
    final raw = jsonDecode(value);
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['enabled'] is! bool ||
        raw['visibleCount'] is! int ||
        raw['items'] is! List ||
        raw['annotations'] is! List ||
        raw['colors'] is! List ||
        (raw['colors'] as List).any((c) => c is! String)) {
      throw const FormatException('Invalid toolbar configuration');
    }
    final config = SelectionToolbarConfig(
        enabled: raw['enabled'],
        visibleCount: raw['visibleCount'],
        items: List<SelectionToolbarItem>.unmodifiable(
            (raw['items'] as List).map(SelectionToolbarItem.fromJson)),
        annotations: List<SelectionToolbarItem>.unmodifiable(
            (raw['annotations'] as List).map(SelectionToolbarItem.fromJson)),
        colors:
            List<String>.unmodifiable((raw['colors'] as List).cast<String>()));
    config.validate();
    return config;
  }
}
