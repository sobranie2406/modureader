import 'package:modu_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:flutter/material.dart';

const readerMenuTitleStyle = TextStyle(
  fontSize: 28,
  fontFamily: 'SourceHanSerif',
  fontWeight: FontWeight.bold,
);

TextStyle? readerSubmenuTitleStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .titleLarge
    ?.copyWith(fontFamily: readerMenuTitleStyle.fontFamily);

Widget widgetTitle(String title, ReadingSettings? settings,
    {VoidCallback? onSettings}) {
  Widget settingsButton = settings == null && onSettings == null
      ? const SizedBox(
          height: 48,
        )
      : SizedBox(
          height: 48,
          child: IconButton(
              onPressed: onSettings ?? () => showMoreSettings(settings!),
              icon: const Icon(Icons.settings)),
        );

  return Column(
    children: [
      Row(
        children: [
          Text(
            title,
            style: readerMenuTitleStyle,
          ),
          const Spacer(),
          settingsButton,
        ],
      ),
      const Divider(),
    ],
  );
}
