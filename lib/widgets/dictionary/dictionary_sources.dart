import 'package:flutter/material.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:anx_reader/service/dictionary/online_dictionary.dart';
import 'package:anx_reader/service/dictionary/dictionary_preferences.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_common.dart';
import 'package:anx_reader/utils/app_motion.dart';

Future<bool> showDictionarySources(
    BuildContext context, List<LocalDictionary> dictionaries) async {
  final prefs = await DictionaryPreferences.load();
  if (!context.mounted) return false;
  final enabled = dictionaries.where((d) => d.enabled).toList();
  final selected = enabled
      .where((d) => prefs.localIds == null || prefs.localIds!.contains(d.id))
      .map((d) => d.id)
      .toSet();
  final online = prefs.online.toSet();
  var saving = false, failed = false;
  return await showDialog<bool>(
          context: context,
          animationStyle: AppMotion.style,
          builder: (context) => StatefulBuilder(builder: (context, setState) {
                String t(String zh, String en) =>
                    dictionaryLabel(context, zh, en);
                return AlertDialog(
                  title: Text(t('查询字典', 'Query dictionaries')),
                  content: SizedBox(
                      width: 480,
                      child: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(t('可勾选一本或多本字典。不会改变导入文件或字典的启用状态。',
                                'Select one or more dictionaries. Imported files and enabled states are unchanged.')),
                            const SizedBox(height: 12),
                            Text(t('本地字典', 'Local dictionaries')),
                            Wrap(children: [
                              TextButton(
                                  onPressed: saving
                                      ? null
                                      : () => setState(() => selected
                                          .addAll(enabled.map((d) => d.id))),
                                  child: Text(t('全选本地', 'Select all local'))),
                              TextButton(
                                  onPressed: saving
                                      ? null
                                      : () => setState(selected.clear),
                                  child:
                                      Text(t('清空本地', 'Clear local selection'))),
                            ]),
                            if (enabled.isEmpty)
                              Text(t('没有已启用的本地字典',
                                  'No enabled local dictionaries')),
                            for (final d in enabled)
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(d.name),
                                  subtitle: Text(d.format),
                                  value: selected.contains(d.id),
                                  onChanged: saving
                                      ? null
                                      : (v) => setState(() {
                                            if (v == true) {
                                              selected.add(d.id);
                                            } else {
                                              selected.remove(d.id);
                                            }
                                          })),
                            const Divider(),
                            Text(t('免费在线字典', 'Free online dictionaries')),
                            Text(t(
                                '启用后会向所选服务发送查询词及网络请求信息，不发送书籍正文。需联网；不可用时仍可查本地字典。',
                                'When enabled, sends the query and network request information to selected services, never book text. Requires internet; local dictionaries remain available if a service fails.')),
                            for (final s in OnlineDictionary.values)
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(t(s.zh, s.en)),
                                  value: online.contains(s),
                                  onChanged: saving
                                      ? null
                                      : (v) => setState(() {
                                            if (v == true) {
                                              online.add(s);
                                            } else {
                                              online.remove(s);
                                            }
                                          })),
                            if (failed)
                              Text(t('保存失败，请重试。', 'Could not save. Try again.'),
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error)),
                          ]))),
                  actions: [
                    TextButton(
                        onPressed:
                            saving ? null : () => Navigator.pop(context, false),
                        child: Text(t('取消', 'Cancel'))),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                setState(() {
                                  saving = true;
                                  failed = false;
                                });
                                try {
                                  await DictionaryPreferences(
                                          localIds: selected, online: online)
                                      .save();
                                  if (context.mounted) {
                                    Navigator.pop(context, true);
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    setState(() {
                                      saving = false;
                                      failed = true;
                                    });
                                  }
                                }
                              },
                        child: Text(t('查询', 'Apply'))),
                  ],
                );
              })) ??
      false;
}
