import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

class ReaderMenuOpacityTile extends StatefulWidget {
  const ReaderMenuOpacityTile({super.key});

  @override
  State<ReaderMenuOpacityTile> createState() => _ReaderMenuOpacityTileState();
}

class _ReaderMenuOpacityTileState extends State<ReaderMenuOpacityTile> {
  late int _percent = Prefs().readerMenuOpacityPercent;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Prefs(),
        builder: (context, _) {
          final disabled = Prefs().eInkMode;
          final percent = disabled ? 100 : _percent;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              enabled: !disabled,
              title: SettingHelp(
                  title: Text(ModuStrings.text(
                      context, '阅读弹出界面不透明度', 'Reading popup opacity')),
                  description: Text(disabled
                      ? ModuStrings.text(context, '电子墨水屏模式下固定为 100%',
                          'Fixed at 100% in e-ink mode')
                      : ModuStrings.text(context, '仅本设备 · 不同步',
                          'This device only · Not synced'))),
              trailing: Text('$percent%'),
            ),
            Slider(
              key: const ValueKey('reader-menu-opacity-percent'),
              value: percent.toDouble(),
              min: 20,
              max: 100,
              divisions: 80,
              label: '$percent%',
              semanticFormatterCallback: (value) => '${value.round()}%',
              onChanged: disabled
                  ? null
                  : (value) => setState(() => _percent = value.round()),
              onChangeEnd: disabled
                  ? null
                  : (value) => Prefs().readerMenuOpacityPercent = value.round(),
            ),
          ]);
        },
      );
}
