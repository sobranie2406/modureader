import 'dart:ui';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/app_language.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/page/home_page/ai_page.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/utils/env_var.dart';
import 'package:modu_reader/widgets/common/container/filled_container.dart';
import 'package:modu_reader/widgets/home_navigation_metrics.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'package:icons_plus/icons_plus.dart';

/// Builds the page for a home navigation destination.
///
/// The shell owns the destinations, the selected tab and the responsive
/// layout; the home page only decides which widget backs each identifier.
typedef HomeNavigationPageBuilder = Widget Function(
  String identifier,
  ScrollController? controller,
);

/// One home navigation destination.
///
/// [identifier] is stable across rebuilds, so hiding or showing a destination
/// from the settings switches keeps the selected tab deterministic.
@immutable
class HomeNavigationDestination {
  const HomeNavigationDestination(this.identifier, this.icon, this.label);

  final String identifier;
  final IconData icon;
  final String label;

  static const String bookshelf = 'bookshelf';
  static const String remoteLibrary = 'remoteLibrary';
  static const String statistics = 'statistics';
  static const String ai = 'ai';
  static const String notes = 'notes';
  static const String settings = 'settings';
}

/// Responsive home navigation: a side rail on wide windows and a floating bar
/// on narrow ones.
///
/// The home route is `const`, so it is never rebuilt when [Prefs] notifies.
/// This shell listens to that notifier itself; otherwise turning a destination
/// off (or on) in Settings would keep showing the stale rail/bar until an
/// unrelated rebuild, which is the "separate tab does not refresh" bug.
class HomeNavigationShell extends StatefulWidget {
  const HomeNavigationShell({super.key, required this.pageBuilder});

  final HomeNavigationPageBuilder pageBuilder;

  @override
  State<HomeNavigationShell> createState() => _HomeNavigationShellState();
}

class _HomeNavigationShellState extends State<HomeNavigationShell> {
  String _currentTab = HomeNavigationDestination.bookshelf;
  EdgeInsets? _homeViewPadding;
  Size? _homeViewport;
  bool _holdingSystemInsets = false;

  MediaQueryData _stableHomeInsets(MediaQueryData media, bool isCurrent) {
    final previous = _homeViewport;
    final resized = previous == null ||
        previous.width != media.size.width ||
        (previous.width > previous.height) !=
            (media.size.width > media.size.height);
    final saved = _homeViewPadding;
    final actual = media.viewPadding;
    final barsRestored = saved == null ||
        ((saved.top == 0 || actual.top > 0) &&
            (saved.bottom == 0 || actual.bottom > 0) &&
            (saved.left == 0 || actual.left > 0) &&
            (saved.right == 0 || actual.right > 0));
    // The covered shelf is also the return Hero's destination. Keep its safe
    // area until native bars return, rather than relaying out after the flight.
    if (resized || (isCurrent && (!_holdingSystemInsets || barsRestored))) {
      _homeViewPadding = actual;
      _holdingSystemInsets = false;
    } else if (!isCurrent) {
      _holdingSystemInsets = true;
    }
    _homeViewport = media.size;
    final insets = _holdingSystemInsets ? _homeViewPadding! : actual;
    return media.copyWith(
      viewPadding: insets,
      padding: EdgeInsets.fromLTRB(
        (insets.left - media.viewInsets.left).clamp(0.0, double.infinity),
        (insets.top - media.viewInsets.top).clamp(0.0, double.infinity),
        (insets.right - media.viewInsets.right).clamp(0.0, double.infinity),
        (insets.bottom - media.viewInsets.bottom).clamp(0.0, double.infinity),
      ),
    );
  }

  List<HomeNavigationDestination> _destinations(BuildContext context) {
    final prefs = Prefs();
    final l10n = L10n.of(context);
    final localeKey = appLocaleKey(Localizations.localeOf(context));
    return <HomeNavigationDestination>[
      HomeNavigationDestination(
        HomeNavigationDestination.bookshelf,
        EvaIcons.book_open,
        l10n.navBarBookshelf,
      ),
      if (prefs.bottomNavigatorShowRemote)
        HomeNavigationDestination(
          HomeNavigationDestination.remoteLibrary,
          Icons.cloud_download_outlined,
          switch (localeKey) {
            'zh-CN' => '远程',
            'zh-TW' || 'zh-LZH' => '遠程',
            _ => ModuStrings.text(context, '远程书库', 'Remote library'),
          },
        ),
      if (prefs.bottomNavigatorShowStatistics)
        HomeNavigationDestination(
          HomeNavigationDestination.statistics,
          Icons.history,
          switch (localeKey) {
            'zh-CN' => '历史',
            'zh-TW' || 'zh-LZH' => '歷史',
            _ => l10n.navBarStatistics,
          },
        ),
      if (prefs.bottomNavigatorShowAI && EnvVar.enableAIFeature)
        HomeNavigationDestination(
          HomeNavigationDestination.ai,
          Icons.auto_awesome,
          l10n.navBarAI,
        ),
      if (prefs.bottomNavigatorShowNote)
        HomeNavigationDestination(
          HomeNavigationDestination.notes,
          Icons.note,
          l10n.navBarNotes,
        ),
      HomeNavigationDestination(
        HomeNavigationDestination.settings,
        EvaIcons.settings_2,
        l10n.navBarSettings,
      ),
    ];
  }

  void _selectDestination(
      HomeNavigationDestination destination, bool fromRail) {
    if (destination.identifier == HomeNavigationDestination.ai && !fromRail) {
      showCupertinoSheet(
        context: context,
        scrollableBuilder: (BuildContext context, ScrollController controller) {
          Widget widgetBuilder(BuildContext context) => const AiPage();
          return widgetBuilder(context);
        },
      );
      return;
    }
    setState(() {
      _currentTab = destination.identifier;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: _stableHomeInsets(MediaQuery.of(context),
          ModalRoute.isCurrentOf(context) ?? true),
      child: _buildNavigation(),
    );
  }

  Widget _buildNavigation() {
    return AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        final destinations = _destinations(context);
        var selectedIndex = destinations
            .indexWhere((destination) => destination.identifier == _currentTab);
        if (selectedIndex == -1) {
          // The selected destination was just hidden by a settings switch (or
          // an imported configuration). Fall back to the stable first entry.
          selectedIndex = 0;
          _currentTab = destinations.first.identifier;
        }

        Widget pageFor(int index, ScrollController? controller) =>
            widget.pageBuilder(destinations[index].identifier, controller);

        return LayoutBuilder(
          builder: (context, constraints) {
            if (Prefs().appLayoutMode.usesWideLayout(constraints.maxWidth)) {
              return Scaffold(
                extendBody: true,
                body: Row(
                  children: [
                    SafeArea(
                      bottom: false,
                      child: FilledContainer(
                        margin: const EdgeInsets.all(16),
                        color: Prefs().eInkMode
                            ? ElevationOverlay.applySurfaceTint(
                                Theme.of(context).colorScheme.surface,
                                Theme.of(context).colorScheme.primary,
                                3,
                              )
                            : Theme.of(context).scaffoldBackgroundColor,
                        radius: 20,
                        child: SafeArea(
                          child: NavigationRail(
                            groupAlignment: 1,
                            extended: false,
                            selectedIndex: selectedIndex,
                            onDestinationSelected: (int index) =>
                                _selectDestination(destinations[index], true),
                            destinations: [
                              for (final destination in destinations)
                                NavigationRailDestination(
                                  icon: Icon(destination.icon),
                                  label: Text(destination.label),
                                ),
                            ],
                            labelType: NavigationRailLabelType.all,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: pageFor(selectedIndex, null)),
                  ],
                ),
              );
            }

            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            // A compact bar never keeps a sheet-only AI destination selected.
            final displayIndex = destinations[selectedIndex].identifier ==
                    HomeNavigationDestination.ai
                ? 0
                : selectedIndex;
            return Scaffold(
              extendBody: true,
              body: BottomBar(
                duration: AppMotion.duration(const Duration(milliseconds: 120)),
                width: 330,
                offset: HomeNavigationMetrics.barOffset,
                body: (_, controller) => HomeNavigationBody(
                  hasBottomBar: !keyboardOpen,
                  scrollBehindBar: true,
                  child: pageFor(displayIndex, controller),
                ),
                showIcon: !keyboardOpen,
                hideOnScroll: Prefs().autoHideBottomBar,
                scrollOpposite: false,
                curve: Curves.easeIn,
                barColor: Colors.transparent,
                iconDecoration: BoxDecoration(
                  color: Prefs().autoHideBottomBar
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(500),
                ),
                child: Visibility(
                  visible: !keyboardOpen,
                  maintainState: true,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: Prefs().eInkMode ? 0 : 12,
                        sigmaY: Prefs().eInkMode ? 0 : 12,
                      ),
                      child: Container(
                        height: HomeNavigationMetrics.barHeightFor(context),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainer
                              .withAlpha(Prefs().eInkMode ? 255 : 100),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withAlpha(Prefs().eInkMode ? 255 : 90),
                            width: 0.5,
                          ),
                        ),
                        child: BottomNavigationBar(
                          selectedFontSize: 12,
                          enableFeedback: false,
                          type: BottomNavigationBarType.fixed,
                          landscapeLayout:
                              BottomNavigationBarLandscapeLayout.linear,
                          currentIndex: displayIndex,
                          onTap: (int index) =>
                              _selectDestination(destinations[index], false),
                          items: [
                            for (final destination in destinations)
                              BottomNavigationBarItem(
                                icon: Icon(destination.icon),
                                label: destination.label,
                              ),
                          ],
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
