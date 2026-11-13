import 'dart:math';

import 'package:modu_reader/enums/hint_key.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/providers/dashboard_tiles_provider.dart';
import 'package:modu_reader/widgets/hint/hint_banner.dart';
import 'package:modu_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staggered_reorderable/staggered_reorderable.dart';

class StatisticsDashboard extends ConsumerWidget {
  const StatisticsDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tilesState = ref.watch(dashboardTilesProvider);
    final notifier = ref.read(dashboardTilesProvider.notifier);
    final workingTiles = tilesState.workingTiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HintBanner(
            icon: const Icon(Icons.drag_handle),
            hintKey: HintKey.statisticsDashboardRearrange,
            margin: const EdgeInsets.only(bottom: 10),
            child: Text(
              ModuStrings.text(context, '点击编辑可选择书籍打开方式、添加卡片；编辑时长按拖动卡片排序。',
                  'Tap Edit to choose how books open or add cards. While editing, hold and drag cards to reorder them.'),
            )),
        workingTiles.isEmpty
            ? _buildEmptyState(context, () => notifier.reorder)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisUnits =
                      _calculateColumnUnits(constraints.maxWidth);
                  return StaggeredReorderableView.customer(
                    columnNum: crossAxisUnits,
                    spacing: 10,
                    canDrag: tilesState.isEditing,
                    children: _buildReorderableItems(
                      context,
                      workingTiles,
                      crossAxisUnits,
                    ),
                    onReorder: notifier.reorder,
                    fixedCellHeight: 90,
                  );
                },
              ),
      ],
    );
  }

  List<ReorderableItem> _buildReorderableItems(
    BuildContext context,
    List<StatisticsDashboardTileType> workingTiles,
    int columnUnits,
  ) {
    return workingTiles
        .map(
          (type) => dashboardTileRegistry[type]!.buildReorderableItem(
            context: context,
          ),
        )
        .toList(growable: false);
  }

  int _calculateColumnUnits(double width) {
    return max(4, (width ~/ 200) * 2);
  }

  Widget _buildEmptyState(BuildContext context, VoidCallback? onAddPressed) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          L10n.of(context).statisticsDashboardEmpty,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAddPressed,
          icon: const Icon(Icons.add),
          label: Text(L10n.of(context).statisticsDashboardAddCard),
        ),
      ],
    );
  }
}
