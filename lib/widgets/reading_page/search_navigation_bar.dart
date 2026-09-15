import 'package:anx_reader/providers/toc_search.dart';
import 'package:flutter/material.dart';

class SearchNavigationBar extends StatelessWidget {
  const SearchNavigationBar(
      {super.key,
      required this.state,
      required this.onSearch,
      required this.onPrevious,
      required this.onNext,
      required this.onReturn,
      required this.onClose});
  final TocSearchState state;
  final VoidCallback onSearch, onPrevious, onNext, onReturn, onClose;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final matches = state.matches;
    final index = state.activeIndex;
    Widget action(
            String id, IconData icon, String label, VoidCallback? callback) =>
        Expanded(
            child: TextButton(
                key: ValueKey('search-nav-$id'),
                onPressed: callback,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon),
                  const SizedBox(height: 2),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12)),
                ])));
    return Material(
      key: const ValueKey('search-navigation-bar'),
      elevation: 4,
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${index < 0 ? 0 : index + 1}/${matches.length}',
                  key: const ValueKey('search-match-counter'),
                  style: Theme.of(context).textTheme.labelMedium),
              if (state.isSearching)
                Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(zh ? '搜索中…' : 'Searching…',
                        style: Theme.of(context).textTheme.labelSmall)),
            ]),
            Row(children: [
              action('search', Icons.search, zh ? '全文搜索' : 'Search', onSearch),
              action('previous', Icons.arrow_back, zh ? '上一个' : 'Previous',
                  !state.isNavigating && index > 0 ? onPrevious : null),
              action(
                  'next',
                  Icons.arrow_forward,
                  zh ? '下一个' : 'Next',
                  !state.isNavigating && index + 1 < matches.length
                      ? onNext
                      : null),
              action('return', Icons.keyboard_return, zh ? '返回原处' : 'Return',
                  state.originCfi?.isNotEmpty == true ? onReturn : null),
              action('close', Icons.close, zh ? '关闭' : 'Close', onClose),
            ]),
          ])),
    );
  }
}
