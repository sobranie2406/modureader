import 'dart:convert';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/widgets/reading_page/classical_translation_icon.dart';
import 'package:flutter/material.dart';

enum ReaderTopAction {
  quickMark,
  ai,
  translation,
  classical,
  search,
  bookmark,
  copy,
  details;

  String label(BuildContext context) => ModuStrings.text(
      context,
      ['快速标记', 'AI 对话', '阅读翻译', '文言文翻译', '搜索', '书签', '复制章节', '书籍详情'][index],
      [
        'Quick mark',
        'AI chat',
        'Reader translation',
        'Classical Chinese',
        'Search',
        'Bookmark',
        'Copy chapter',
        'Book details'
      ][index]);
  Widget get icon => this == classical
      ? const ClassicalTranslationIcon()
      : Icon([
          Icons.draw_outlined,
          Icons.auto_awesome,
          Icons.translate_outlined,
          Icons.translate,
          Icons.search,
          Icons.bookmark_border,
          Icons.copy,
          Icons.info_outline
        ][index]);
}

class ReaderTopActionsConfig {
  ReaderTopActionsConfig({required this.order, required this.hidden});
  factory ReaderTopActionsConfig.parse(String json) {
    try {
      final map = jsonDecode(json) as Map;
      final names = map['order'] is List ? map['order'] as List : const [];
      final hidden = map['hidden'] is List ? map['hidden'] as List : const [];
      return ReaderTopActionsConfig(
          order: {
            for (final name in names)
              ...ReaderTopAction.values.where((a) => a.name == name),
            ...ReaderTopAction.values,
          }.toList(),
          hidden: ReaderTopAction.values
              .where((a) => hidden.contains(a.name))
              .toSet());
    } catch (_) {
      return ReaderTopActionsConfig(
          order: ReaderTopAction.values.toList(), hidden: {});
    }
  }
  final List<ReaderTopAction> order;
  final Set<ReaderTopAction> hidden;
  List<ReaderTopAction> visible(Iterable<ReaderTopAction> available) =>
      order.where((a) => !hidden.contains(a) && available.contains(a)).toList();
  String encode() => jsonEncode({
        'order': order.map((a) => a.name).toList(),
        'hidden': hidden.map((a) => a.name).toList()
      });
}

class ReaderTopActions extends StatelessWidget {
  const ReaderTopActions(
      {super.key,
      required this.readerWidth,
      required this.buttons,
      required this.actions});
  final double readerWidth;
  final Map<ReaderTopAction, Widget> buttons;
  final Map<ReaderTopAction, VoidCallback?> actions;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Prefs(),
      builder: (context, _) {
        final visible = ReaderTopActionsConfig.parse(Prefs().readerToolbar)
            .visible(buttons.keys);
        final capacity = (readerWidth * .4 / kMinInteractiveDimension).floor();
        final hasMore = visible.length > capacity;
        // Reserve a touch target for More only when actions actually overflow.
        final directCount =
            hasMore ? (capacity - 1).clamp(0, visible.length) : visible.length;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          for (final action in visible.take(directCount))
            SizedBox.square(
                dimension: kMinInteractiveDimension, child: buttons[action]!),
          if (hasMore)
            SizedBox.square(
                dimension: kMinInteractiveDimension,
                child: PopupMenuButton<ReaderTopAction>(
                  key: const ValueKey('reader-top-more'),
                  tooltip: ModuStrings.text(context, '更多', 'More'),
                  icon: const Icon(Icons.more_vert),
                  clipBehavior: Clip.antiAlias,
                  popUpAnimationStyle: AppMotion.style,
                  onSelected: (action) => actions[action]?.call(),
                  itemBuilder: (_) => [
                    for (final action in visible.skip(directCount))
                      PopupMenuItem(
                          value: action,
                          enabled: actions[action] != null,
                          child: Row(children: [
                            action.icon,
                            const SizedBox(width: 12),
                            Flexible(child: Text(action.label(context)))
                          ])),
                  ],
                )),
        ]);
      });
}

class ReaderTopActionsSettings extends StatefulWidget {
  const ReaderTopActionsSettings({super.key});
  @override
  State<ReaderTopActionsSettings> createState() =>
      _ReaderTopActionsSettingsState();
}

class _ReaderTopActionsSettingsState extends State<ReaderTopActionsSettings> {
  late ReaderTopActionsConfig config =
      ReaderTopActionsConfig.parse(Prefs().readerToolbar);
  void save() {
    Prefs().readerToolbar = config.encode();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(ModuStrings.text(
            context,
            '按顺序显示已启用的按钮，功能区（含「更多」）最多占阅读区域宽度的 40%，其余放入「更多」。返回按钮独立保留。拖动右侧手柄排序。',
            'Enabled actions appear in order within 40% of the reading area width, including More. Remaining actions go in More. Back stays separate. Drag the handles to reorder.')),
        ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: config.order.length,
            onReorderItem: (oldIndex, newIndex) {
              config.order.insert(newIndex, config.order.removeAt(oldIndex));
              save();
            },
            itemBuilder: (context, index) {
              final action = config.order[index];
              return ListTile(
                  key: ValueKey(action),
                  leading: action.icon,
                  title: Text(action.label(context)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(
                        value: !config.hidden.contains(action),
                        onChanged: (value) {
                          value
                              ? config.hidden.remove(action)
                              : config.hidden.add(action);
                          save();
                        }),
                    ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.drag_handle))),
                  ]));
            }),
      ]);
}
