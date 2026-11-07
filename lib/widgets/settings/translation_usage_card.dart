import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/translate/translation_usage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class TranslationUsageCard extends StatefulWidget {
  const TranslationUsageCard(
      {super.key, required this.engine, required this.config});
  final String engine;
  final Map<String, String> config;
  @override
  State<TranslationUsageCard> createState() => _TranslationUsageCardState();
}

class _TranslationUsageCardState extends State<TranslationUsageCard> {
  String label(String zh, String en) => ModuStrings.text(context, zh, en);
  Future<void> editQuota(TranslationUsage usage, String account) async {
    final controller = TextEditingController(
        text: usage.quota(account, widget.engine).toString());
    final value = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(label('参考免费额度', 'Reference free allowance')),
              content: TextField(
                key: const ValueKey('translation-usage-quota-input'),
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(13)
                ],
                decoration: InputDecoration(
                    labelText: label('字符数，以官方套餐为准',
                        'Characters — check your official plan')),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(label('取消', 'Cancel'))),
                ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final number = int.tryParse(value.text) ?? 0;
                      return TextButton(
                          onPressed: number > 0 && number <= 1000000000000
                              ? () => Navigator.pop(dialogContext, number)
                              : null,
                          child: Text(label('保存', 'Save')));
                    }),
              ],
            ));
    // Let the dialog finish its exit animation before disposing its controller.
    if (value != null) {
      await usage.setQuota(account, value);
      if (mounted) setState(() {});
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([Prefs(), TranslationUsage.changes]),
      builder: (context, _) {
        final usage = TranslationUsage(Prefs().prefs);
        final account = TranslationUsage.account(widget.engine, widget.config);
        final configured = (widget.config[widget.engine == 'baidu'
                    ? 'baidu_appid'
                    : 'microsoft_key'] ??
                '')
            .trim()
            .isNotEmpty;
        final used = configured ? usage.used(account) : 0;
        final quota = usage.quota(account, widget.engine);
        final format = NumberFormat.decimalPattern();
        final ratio = used / quota;
        return Card.outlined(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        label('翻译用量（已同步设备估算）',
                            'Translation usage (synced-device estimate)'),
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text(
                        '${TranslationUsage.month()} · ${label('UTC 自然月', 'UTC calendar month')}'),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                        key: const ValueKey('translation-usage-progress'),
                        value: ratio.clamp(0.0, 1.0),
                        color: ratio >= 1
                            ? Theme.of(context).colorScheme.error
                            : null,
                        semanticsLabel: label('估算用量占参考额度',
                            'Estimated usage against reference allowance')),
                    const SizedBox(height: 8),
                    Text(
                        '${format.format(used)} / ${format.format(quota)} ${label('字符', 'characters')} · ${(ratio * 100).toStringAsFixed(1)}%'),
                    const SizedBox(height: 8),
                    SettingHelp(
                        title: Text(ModuStrings.text(context, "用量统计", "Usage")),
                        description: Text(label("开启服务设置同步，可汇总各设备的翻译用量。",
                            "Enable service settings sync to combine translation usage across devices."))),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      TextButton(
                          onPressed: configured
                              ? () => editQuota(usage, account)
                              : null,
                          child:
                              Text(label('设置参考额度', 'Set reference allowance'))),
                      TextButton(
                          onPressed: () => launchUrl(
                              Uri.parse(widget.engine == 'baidu'
                                  ? 'https://fanyi-api.baidu.com/manage/developer'
                                  : 'https://portal.azure.com/'),
                              mode: LaunchMode.externalApplication),
                          child:
                              Text(label('官方用量控制台', 'Official usage console'))),
                    ]),
                  ],
                )));
      });
}
