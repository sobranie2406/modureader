import 'package:modu_reader/widgets/common/container/filled_container.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';

abstract class AbstractSettingsSection extends StatelessWidget {
  const AbstractSettingsSection({super.key});
}

class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 12, 24, 5),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
          child: child,
        ),
      );
}

class SettingsSection extends AbstractSettingsSection {
  const SettingsSection({
    super.key,
    required this.tiles,
    this.margin,
    this.title,
  });

  SettingsSection.content({
    Key? key,
    required Widget title,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) : this(
          key: key,
          title: title,
          tiles: [
            CustomSettingsTile(child: Padding(padding: padding, child: child))
          ],
        );

  final List<AbstractSettingsTile> tiles;
  final EdgeInsetsDirectional? margin;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    return buildSectionBody(context);
  }

  Widget buildSectionBody(BuildContext context) {
    final tileList = buildTileList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) SettingsSectionTitle(child: title!),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FilledContainer(
            padding: EdgeInsetsGeometry.zero,
            child: Material(type: MaterialType.transparency, child: tileList),
          ),
        ),
      ],
    );
  }

  Widget buildTileList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: tiles,
    );
  }
}

class CustomSettingsSection extends AbstractSettingsSection {
  const CustomSettingsSection({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
