import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

class ReaderPopupHeightTile extends StatefulWidget {
  const ReaderPopupHeightTile({super.key});

  @override
  State<ReaderPopupHeightTile> createState() => _ReaderPopupHeightTileState();
}

class _ReaderPopupHeightTileState extends State<ReaderPopupHeightTile> {
  late int _percent = Prefs().readerPopupMaxHeightPercent;

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: SettingHelp(
              title: Text(ModuStrings.text(
                  context, '弹出菜单高度上限', 'Maximum popup height')),
              description: Text(ModuStrings.text(
                  context, '仅本设备 · 不同步', 'This device only · Not synced'))),
          trailing: Text('$_percent%'),
        ),
        Slider(
          key: const ValueKey('reader-popup-height-percent'),
          value: _percent.toDouble(),
          min: 40,
          max: 80,
          divisions: 40,
          label: '$_percent%',
          semanticFormatterCallback: (value) => '${value.round()}%',
          onChanged: (value) => setState(() => _percent = value.round()),
          onChangeEnd: (value) =>
              Prefs().readerPopupMaxHeightPercent = value.round(),
        ),
      ]);
}
