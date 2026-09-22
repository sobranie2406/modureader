import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/app_brightness.dart';
import 'package:flutter/material.dart';

/// Wraps the navigator and dialogs, but never intercepts their input. Keeping
/// [child] outside the listener avoids rebuilding the reader while dragging.
class AppBrightnessLayer extends StatelessWidget {
  const AppBrightnessLayer(
      {super.key, required this.child, required this.controller});

  final Widget child;
  final AppBrightness controller;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (_, __) => ColoredBox(
                    color:
                        Colors.black.withValues(alpha: controller.dimOpacity),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

class BrightnessWidget extends StatelessWidget {
  const BrightnessWidget({super.key, required this.controller});

  final AppBrightness controller;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.readingBrightness),
              subtitle: Text(l10n.readingBrightnessFollowSystem),
              value: controller.followSystem,
              onChanged: controller.setFollowSystem,
            ),
            Row(
              children: [
                const Icon(Icons.brightness_low),
                Expanded(
                  child: Slider(
                    min: AppBrightness.minimum,
                    max: 1,
                    value: controller.level,
                    label: '${(controller.level * 100).round()}%',
                    semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                    onChanged: controller.setLevel,
                    onChangeEnd: (_) => unawaited(controller.save()),
                  ),
                ),
                Text('${(controller.level * 100).round()}%'),
              ],
            ),
            Text(
              controller.usesWindowBrightness
                  ? l10n.readingBrightnessWindowHint
                  : l10n.readingBrightnessDimHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
