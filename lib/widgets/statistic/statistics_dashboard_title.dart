import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/providers/dashboard_tiles_provider.dart';
import 'package:anx_reader/providers/total_reading_time.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/highlight_digit.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:introduction_screen/introduction_screen.dart';

// Provider to track current page index in IntroductionScreen
final _currentPageIndexProvider = StateProvider<int>((ref) => 0);

class StatisticsDashboardTitle extends ConsumerStatefulWidget {
  const StatisticsDashboardTitle({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _StatisticDashboardTitleState();
}

class _StatisticDashboardTitleState
    extends ConsumerState<StatisticsDashboardTitle> {
  @override
  Widget build(BuildContext context) {
    final tilesState = ref.watch(dashboardTilesProvider);
    final notifier = ref.read(dashboardTilesProvider.notifier);
    final availableTiles = notifier.availableTiles;
    final l10n = L10n.of(context);

    void showAddTileSheet() {
      if (availableTiles.isEmpty) return;
      showModalBottomSheet(
        sheetAnimationStyle: AppMotion.style,
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return AddTileSheetContent();
        },
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The pencil sits right after the date so it never claims a row of
          // its own: the date row is short and the button is compact.
          TotalReadTime(
            trailing: tilesState.isEditing
                ? null
                : IconButton(
                    key: const ValueKey('history-edit'),
                    onPressed: notifier.startEditing,
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: l10n.commonEdit,
                    iconSize: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
          ),
          if (tilesState.isEditing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ModuStrings.text(
                          context, '点击书籍时', 'When tapping a book')),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: AnxSegmentedButton<bool>(
                          key: const ValueKey('history-book-tap-action'),
                          segments: [
                            SegmentButtonItem(
                                value: false,
                                label: l10n.readingPageBookDetails),
                            SegmentButtonItem(
                                value: true,
                                label: ModuStrings.text(
                                    context, '直接阅读', 'Read directly')),
                          ],
                          selected: {tilesState.openBookDirectly},
                          onSelectionChanged: (values) =>
                              notifier.setOpenBookDirectly(values.single),
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: notifier.restoreDefaults,
                    icon: const Icon(Icons.restore),
                    label: Text(
                        ModuStrings.text(context, '恢复默认', 'Restore defaults')),
                  ),
                  IconButton(
                    onPressed: availableTiles.isEmpty ? null : showAddTileSheet,
                    icon: const Icon(Icons.add),
                    tooltip: l10n.statisticsDashboardAddCard,
                  ),
                  IconButton(
                    onPressed: notifier.saveLayout,
                    icon: const Icon(Icons.save),
                    tooltip: l10n.commonSave,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class AddTileSheetContent extends ConsumerStatefulWidget {
  const AddTileSheetContent({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _AddTileSheetContentState();
}

class _AddTileSheetContentState extends ConsumerState<AddTileSheetContent> {
  late final List<StatisticsDashboardTileType> availableTiles;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(dashboardTilesProvider.notifier);
    availableTiles = notifier.availableTiles;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(dashboardTilesProvider.notifier);

    final currentIndex = ref.watch(_currentPageIndexProvider);

    // Bounds checking to prevent IndexError
    if (availableTiles.isEmpty) {
      return const SizedBox.shrink();
    }

    // Ensure currentIndex is within valid bounds
    final validIndex = currentIndex.clamp(0, availableTiles.length - 1);
    if (currentIndex != validIndex) {
      // Schedule index correction for next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(_currentPageIndexProvider.notifier).state = validIndex;
        }
      });
    }
    final l10n = L10n.of(context);

    return FilledContainer(
      color: Theme.of(context).scaffoldBackgroundColor,
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Text(
                  l10n.statisticsDashboardAddTileTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          // Introduction Screen
          Expanded(
            child: IntroductionScreen(
              showDoneButton: false,
              pages: availableTiles.map((type) {
                final dashboardTile = dashboardTileRegistry[type]!;
                final metadata = dashboardTile.metadata;
                return PageViewModel(
                    titleWidget: Text(
                      metadata.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    bodyWidget: Column(
                      children: [
                        SizedBox(
                            height: dashboardTile.tileSize(context).height,
                            width: dashboardTile.tileSize(context).width,
                            child: dashboardTile.buildTile(context, ref)),
                        SizedBox(height: 40),
                        Text(
                          metadata.description,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    decoration: PageDecoration(
                      bodyPadding: EdgeInsets.all(0),
                      pageMargin: EdgeInsets.all(0),
                    ));
              }).toList(),
              onDone: () {
                // Navigator.pop(context);
              },
              onChange: (index) {
                ref.read(_currentPageIndexProvider.notifier).state = index;
              },
              showBackButton: false,
              showNextButton: false,
              dotsDecorator: DotsDecorator(
                size: const Size.square(10.0),
                activeSize: const Size(20.0, 10.0),
                activeColor: Theme.of(context).primaryColor,
                color: Colors.black26,
                spacing: const EdgeInsets.symmetric(horizontal: 3.0),
                activeShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25.0),
                ),
              ),
            ),
          ),
          // Add Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: AnxButton.icon(
                disabled:
                    notifier.workingTiles.contains(availableTiles[validIndex]),
                onPressed: () {
                  notifier.addTile(availableTiles[validIndex]);
                  setState(() {});
                },
                icon: const Icon(Icons.add),
                label: Text(
                  l10n.statisticsDashboardAddTileButton(
                    dashboardTileRegistry[availableTiles[validIndex]]!
                        .metadata
                        .title,
                  ),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TotalReadTime extends ConsumerWidget {
  const TotalReadTime({super.key, this.trailing});

  /// Rendered on the same line as the "since date" caption.
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    TextStyle textStyle = const TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.bold,
    );

    TextStyle digitStyle = const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
    );

    return AsyncSkeletonWrapper<int>(
        asyncValue: ref.watch(totalReadingTimeProvider),
        builder: (seconds, _) {
          final hours = seconds ~/ 3600;
          final minutes = (seconds % 3600) ~/ 60;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                // Intrinsic width: a full-width headline row used to push the
                // edit button onto its own line in the old space-between Wrap.
                mainAxisSize: MainAxisSize.min,
                children: [
                  highlightDigit(
                    context,
                    L10n.of(context).commonHours(hours),
                    digitStyle,
                    textStyle,
                  ),
                  highlightDigit(
                    context,
                    L10n.of(context).commonMinutes(minutes),
                    digitStyle,
                    textStyle,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '${Prefs().beginDate.toString().substring(0, 10)} ${L10n.of(context).statisticToPresent}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              )
            ],
          );
        });
  }
}
