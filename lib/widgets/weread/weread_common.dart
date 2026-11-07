import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/weread/weread_api.dart';
import 'package:flutter/material.dart';

String wereadError(BuildContext context, Object error) {
  final code = error is WereadException ? error.code : '';
  return switch (code) {
    'unauthorized' => ModuStrings.text(context, '请在外观设置中检查微信读书 API Key。',
        'Check your WeRead API Key in Appearance settings.'),
    'upgradeRequired' => ModuStrings.text(context, '微信读书接口要求更新客户端，已停止请求。',
        'WeRead requires a client update. Requests stopped.'),
    'invalidQuery' => ModuStrings.text(context, '请输入书名或作者（不超过 500 字）。',
        'Enter a title or author (up to 500 characters).'),
    _ => ModuStrings.text(context, "微信读书资料暂不可用，请稍后重试。",
        "WeRead information is unavailable. Try again later."),
  };
}

Widget wereadPublication(BuildContext context, Map<String, dynamic> info,
    {bool includeIdentity = true}) {
  final missing =
      ModuStrings.text(context, '未提供，请自行核对', 'Not provided; verify manually');
  String value(String key) {
    final text = wereadText(info[key]).trim();
    return text.isEmpty ? missing : text;
  }

  final fields = <String, String>{
    if (includeIdentity) ...{
      ModuStrings.text(context, '书名', 'Title'): value('title'),
      ModuStrings.text(context, '作者', 'Author'): value('author'),
    },
    ModuStrings.text(context, '译者', 'Translator'): value('translator'),
    'ISBN': value('isbn'),
    ModuStrings.text(context, '出版社', 'Publisher'): value('publisher'),
    ModuStrings.text(context, '出版时间', 'Published'): value('publishTime'),
  };
  final theme = Theme.of(context);
  return LayoutBuilder(builder: (context, constraints) {
    final stacked = constraints.maxWidth < 300 ||
        MediaQuery.textScalerOf(context).scale(14) > 21;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in fields.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(field.key, style: theme.textTheme.bodySmall),
                      SelectableText(field.value,
                          style: theme.textTheme.bodyMedium),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(field.key,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SelectableText(field.value,
                            style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
          ),
      ],
    );
  });
}

Future<bool> confirmWeread(
        BuildContext context, String title, Widget content) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content:
            SizedBox(width: 480, child: SingleChildScrollView(child: content)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(ModuStrings.text(context, '确认', 'Confirm'))),
        ],
      ),
    ) ??
    false;
