import 'package:anx_reader/utils/app_motion.dart';
import 'dart:math' as math;
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

/// Explanations stay anchored to their control, with outside-tap dismissal.
class SettingHelp extends StatelessWidget {
  const SettingHelp(
      {super.key, required this.title, required this.description});
  final Widget title;
  final Widget description;

  @override
  Widget build(BuildContext context) => Row(children: [
        Flexible(child: title),
        PopupMenuButton<void>(
          tooltip: ModuStrings.text(context, '说明', 'Help'),
          icon: const Icon(Icons.help_outline, size: 20),
          position: PopupMenuPosition.under,
          popUpAnimationStyle: AppMotion.style,
          constraints: BoxConstraints(
            minWidth: 0,
            maxWidth: math.min(360, MediaQuery.sizeOf(context).width - 32),
            maxHeight: MediaQuery.sizeOf(context).height * .6,
          ),
          itemBuilder: (context) => [
            PopupMenuItem<void>(
              enabled: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyMedium!,
                  child: description,
                ),
              ),
            ),
          ],
        ),
      ]);
}

class SettingHelpTitle extends StatelessWidget {
  const SettingHelpTitle(
      {super.key, required this.title, required this.description});
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) =>
      SettingHelp(title: Text(title), description: Text(description));
}
