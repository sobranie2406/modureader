import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashboardTilesState {
  const DashboardTilesState({
    required this.savedTiles,
    required this.workingTiles,
    required this.hasUnsavedChanges,
    required this.isEditing,
    this.savedOpenBookDirectly = false,
    this.openBookDirectly = false,
  });

  final List<StatisticsDashboardTileType> savedTiles;
  final List<StatisticsDashboardTileType> workingTiles;
  final bool hasUnsavedChanges;
  final bool isEditing;
  final bool savedOpenBookDirectly;
  final bool openBookDirectly;

  DashboardTilesState copyWith({
    List<StatisticsDashboardTileType>? savedTiles,
    List<StatisticsDashboardTileType>? workingTiles,
    bool? hasUnsavedChanges,
    bool? isEditing,
    bool? savedOpenBookDirectly,
    bool? openBookDirectly,
  }) {
    return DashboardTilesState(
      savedTiles: savedTiles ?? this.savedTiles,
      workingTiles: workingTiles ?? this.workingTiles,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      isEditing: isEditing ?? this.isEditing,
      savedOpenBookDirectly:
          savedOpenBookDirectly ?? this.savedOpenBookDirectly,
      openBookDirectly: openBookDirectly ?? this.openBookDirectly,
    );
  }
}

class DashboardTilesNotifier extends StateNotifier<DashboardTilesState> {
  DashboardTilesNotifier()
      : _prefs = Prefs(),
        super(_initialState()) {
    _prefs.addListener(_handlePrefsChange);
  }

  final Prefs _prefs;

  static DashboardTilesState _initialState() {
    final prefs = Prefs();
    final tiles = _sanitize(prefs.statisticsDashboardTiles);
    return DashboardTilesState(
      savedTiles: tiles,
      workingTiles: List.of(tiles),
      savedOpenBookDirectly: prefs.historyOpenBookDirectly,
      openBookDirectly: prefs.historyOpenBookDirectly,
      hasUnsavedChanges: false,
      isEditing: false,
    );
  }

  static List<StatisticsDashboardTileType> _sanitize(
    List<StatisticsDashboardTileType> source,
  ) {
    final seen = <StatisticsDashboardTileType>{};
    final filtered = <StatisticsDashboardTileType>[];
    for (final type in source) {
      if (!dashboardTileRegistry.containsKey(type)) continue;
      if (seen.add(type)) {
        filtered.add(type);
      }
    }
    if (filtered.isEmpty) {
      return List.of(defaultStatisticsDashboardTiles);
    }
    return filtered;
  }

  void _handlePrefsChange() {
    final sanitized = _sanitize(_prefs.statisticsDashboardTiles);
    final openDirectly = _prefs.historyOpenBookDirectly;
    if (state.isEditing) {
      state = state.copyWith(
        savedTiles: sanitized,
        savedOpenBookDirectly: openDirectly,
        hasUnsavedChanges: !listEquals(state.workingTiles, sanitized) ||
            state.openBookDirectly != openDirectly,
      );
    } else {
      state = DashboardTilesState(
        savedTiles: sanitized,
        workingTiles: List.of(sanitized),
        hasUnsavedChanges: false,
        isEditing: false,
        savedOpenBookDirectly: openDirectly,
        openBookDirectly: openDirectly,
      );
    }
  }

  List<StatisticsDashboardTileType> get workingTiles => state.workingTiles;

  List<StatisticsDashboardTileType> get availableTiles {
    final list = List<StatisticsDashboardTileType>.from(
      dashboardTileRegistry.keys.where(
        (type) => !state.workingTiles.contains(type),
      ),
    );
    list.sort((a, b) => a.index.compareTo(b.index));
    return list;
  }

  void reorder(List<int> order) {
    _ensureEditing();
    final map = {
      for (final type in state.workingTiles) type.index: type,
    };
    final reordered = <StatisticsDashboardTileType>[];
    for (final index in order) {
      final type = map[index];
      if (type != null && !reordered.contains(type)) {
        reordered.add(type);
      }
    }
    for (final type in state.workingTiles) {
      if (!reordered.contains(type)) {
        reordered.add(type);
      }
    }
    _updateWorking(reordered);
  }

  void addTile(StatisticsDashboardTileType type) {
    if (state.workingTiles.contains(type)) return;
    _ensureEditing();
    _updateWorking(List.of(state.workingTiles)..add(type));
  }

  void removeTile(StatisticsDashboardTileType type) {
    if (state.workingTiles.length <= 1) return;
    _ensureEditing();
    final updated = List.of(state.workingTiles)..remove(type);
    _updateWorking(updated);
  }

  void saveLayout() {
    final sanitized = _sanitize(state.workingTiles);
    state = DashboardTilesState(
      savedTiles: sanitized,
      workingTiles: List.of(sanitized),
      savedOpenBookDirectly: state.openBookDirectly,
      openBookDirectly: state.openBookDirectly,
      hasUnsavedChanges: false,
      isEditing: false,
    );
    final openDirectly = state.openBookDirectly;
    if (_prefs.historyOpenBookDirectly != openDirectly) {
      _prefs.historyOpenBookDirectly = openDirectly;
    }
    _prefs.statisticsDashboardTiles = sanitized;
  }

  void discardChanges() {
    state = state.copyWith(
      workingTiles: List.of(state.savedTiles),
      openBookDirectly: state.savedOpenBookDirectly,
      hasUnsavedChanges: false,
      isEditing: false,
    );
  }

  void restoreDefaults() {
    _updateWorking(List.of(defaultStatisticsDashboardTiles));
    saveLayout();
  }

  void _updateWorking(List<StatisticsDashboardTileType> next) {
    final sanitized = _sanitize(next);
    final dirty = !listEquals(sanitized, state.savedTiles) ||
        state.openBookDirectly != state.savedOpenBookDirectly;
    state = state.copyWith(
      workingTiles: sanitized,
      hasUnsavedChanges: dirty,
      isEditing: state.isEditing || dirty,
    );
  }

  void _ensureEditing() {
    if (!state.isEditing) {
      state = state.copyWith(isEditing: true);
    }
  }

  void startEditing() => _ensureEditing();

  void setOpenBookDirectly(bool value) {
    _ensureEditing();
    state = state.copyWith(
      openBookDirectly: value,
      hasUnsavedChanges: value != state.savedOpenBookDirectly ||
          !listEquals(state.workingTiles, state.savedTiles),
    );
  }

  @override
  void dispose() {
    _prefs.removeListener(_handlePrefsChange);
    super.dispose();
  }
}

final dashboardTilesProvider =
    StateNotifierProvider<DashboardTilesNotifier, DashboardTilesState>(
        (ref) => DashboardTilesNotifier());
