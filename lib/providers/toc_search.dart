import 'package:anx_reader/models/search_result_model.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'toc_search.g.dart';

@immutable
class TocSearchState {
  const TocSearchState({
    this.query,
    this.progress = 0.0,
    this.results = const [],
    this.isSearching = false,
    this.scrollOffset = 0.0,
    this.originCfi,
    this.activeCfi,
    this.requestId = 0,
    this.isNavigating = false,
  });

  final String? query;
  final double progress;
  final List<SearchResultModel> results;
  final bool isSearching;
  final double scrollOffset;
  final String? originCfi;
  final String? activeCfi;
  final int requestId;
  final bool isNavigating;
  List<SearchResultSubitemModel> get matches =>
      results.expand((group) => group.subitems).toList(growable: false);
  int get activeIndex => matches.indexWhere((item) => item.cfi == activeCfi);

  bool get isActive => query != null && query!.isNotEmpty;

  TocSearchState copyWith({
    Object? query = _noValue,
    double? progress,
    List<SearchResultModel>? results,
    bool? isSearching,
    double? scrollOffset,
    Object? activeCfi = _noValue,
    bool? isNavigating,
  }) {
    return TocSearchState(
      query: identical(query, _noValue) ? this.query : query as String?,
      progress: progress ?? this.progress,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      originCfi: originCfi,
      activeCfi: identical(activeCfi, _noValue)
          ? this.activeCfi
          : activeCfi as String?,
      requestId: requestId,
      isNavigating: isNavigating ?? this.isNavigating,
    );
  }
}

const _noValue = Object();

@Riverpod(keepAlive: true)
class TocSearch extends _$TocSearch {
  @override
  TocSearchState build() => const TocSearchState();

  void start(String query, {String? originCfi}) {
    final sanitized = query.trim();
    state = TocSearchState(
      query: sanitized,
      progress: 0.0,
      results: const [],
      isSearching: true,
      originCfi: state.originCfi ?? originCfi,
      requestId: state.requestId + 1,
    );
  }

  void updateProgress(double progress) {
    state = state.copyWith(
      progress: progress,
      isSearching: progress < 1.0,
    );
  }

  void addResult(SearchResultModel result) {
    final updated = List<SearchResultModel>.from(state.results)..add(result);
    state = state.copyWith(
      results: List<SearchResultModel>.unmodifiable(updated),
    );
  }

  void updateScrollOffset(double offset) {
    state = state.copyWith(scrollOffset: offset);
  }

  void clear() {
    state = TocSearchState(requestId: state.requestId + 1);
  }

  void selectMatch(String cfi) => state = state.copyWith(activeCfi: cfi);
  void setNavigating(bool busy) => state = state.copyWith(isNavigating: busy);
}
