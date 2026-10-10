import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/reader_shortcuts.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ReaderShortcutsSettings extends StatefulWidget {
  const ReaderShortcutsSettings({super.key});
  @override
  State<ReaderShortcutsSettings> createState() =>
      _ReaderShortcutsSettingsState();
}

class _ReaderShortcutsSettingsState extends State<ReaderShortcutsSettings> {
  late ReaderShortcuts shortcuts = Prefs().readerShortcuts;
  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  void save() {
    Prefs().readerShortcuts = shortcuts;
    epubPlayerKey.currentState?.changeStyle(null);
    setState(() {});
  }

  Future<void> add(ReaderAction action) async {
    String? error;
    final key = await showDialog<ReaderKey>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => Focus(
                autofocus: true,
                descendantsAreFocusable: false,
                onKeyEvent: (_, event) {
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    return KeyEventResult.ignored;
                  }
                  if (event is! KeyDownEvent) return KeyEventResult.handled;
                  final key = ReaderKey.fromEvent(event);
                  if (key == null) return KeyEventResult.handled;
                  final conflict = shortcuts.actions(
                      ctrlBrackets: Prefs().keyboardShortcutTurnPage)[key.id];
                  if (conflict != null) {
                    final owner = ReaderAction.values.byName(conflict);
                    update(() => error =
                        '${key.label} · ${t('已用于', 'Already assigned to')} ${t(owner.zh, owner.en)}');
                  } else {
                    Navigator.pop(context, key);
                  }
                  return KeyEventResult.handled;
                },
                child: AlertDialog(
                  title: Text(t('按下要绑定的按键', 'Press a shortcut')),
                  content: Text(error ??
                      t('支持方向键、Page Up/Down、空格、Enter、Home/End、字母、数字、F1–F12、[ ]，可组合 Ctrl / Shift / Alt / Meta。Esc 取消。',
                          'Use arrows, Page Up/Down, Space, Enter, Home/End, letters, digits, F1–F12 or [ ], with optional Ctrl / Shift / Alt / Meta. Esc cancels.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(t('取消', 'Cancel')))
                  ],
                ))));
    if (key == null || !mounted) return;
    shortcuts.bindings[action]!.add(key);
    save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(t('自定义按键', 'Keyboard shortcuts'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(t('用于桌面端和安卓实体键盘。每项最多绑定 8 个按键；输入文字、选词或弹窗时不触发。朗读按键只控制已启动的朗读。',
              'For desktop and Android physical keyboards. Assign up to 8 shortcuts per action. Inactive while editing, selecting text or using dialogs. Narration controls require an active narration session.')),
          for (final action in ReaderAction.values)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t(action.zh, action.en),
                          style: Theme.of(context).textTheme.titleSmall),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final key in shortcuts.bindings[action]!)
                          InputChip(
                              label: Text(key.label),
                              onDeleted: () {
                                shortcuts.bindings[action]!.remove(key);
                                save();
                              }),
                        if (shortcuts.bindings[action]!.length < 8)
                          ActionChip(
                              avatar: const Icon(Icons.add, size: 18),
                              label: Text(t('添加按键', 'Add shortcut')),
                              onPressed: () => add(action)),
                      ]),
                    ])),
          TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                            title: Text(
                                t('恢复默认按键？', 'Restore default shortcuts?')),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(t('取消', 'Cancel'))),
                              TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(t('恢复默认', 'Restore defaults')))
                            ]));
                if (confirmed == true && mounted) {
                  shortcuts = ReaderShortcuts.defaults();
                  save();
                }
              },
              child: Text(t('恢复默认按键', 'Restore default shortcuts'))),
        ]),
      );
}
