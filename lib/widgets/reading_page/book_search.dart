import 'dart:math' as math;
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/search_result_model.dart';
import 'package:anx_reader/providers/toc_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Search is a transient reader overlay, not part of the table-of-contents drawer.
Future<void> showBookSearchDialog(
  BuildContext context, {
  required ValueChanged<String> onSearch,
  required VoidCallback onClear,
  required Future<void> Function(String) onNavigate,
}) {
  final container = ProviderScope.containerOf(context);
  return showDialog<void>(
    context: context,
    useRootNavigator: false,
    requestFocus: true,
    barrierColor: Colors.black26,
    builder: (dialogContext) => UncontrolledProviderScope(
      container: container,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(dialogContext).pop(),
        },
        child: Consumer(builder: (context, ref, _) {
          final active = ref.watch(tocSearchProvider.select((s) => s.isActive));
          final media = MediaQuery.of(context);
          final availableHeight = math.max(
              0.0,
              media.size.height -
                  media.viewInsets.vertical -
                  media.padding.vertical -
                  48);
          final height = math.min(availableHeight, active ? 520.0 : 208.0);
          final search = BookSearch(
            onSearch: onSearch,
            onClear: onClear,
            onNavigate: (cfi) async {
              await onNavigate(cfi);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            onClose: () => Navigator.of(dialogContext).pop(),
          );
          return Dialog(
            key: const ValueKey('book-search-dialog'),
            alignment: const Alignment(0, -0.55),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            clipBehavior: Clip.antiAlias,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: PointerInterceptor(
              child: SizedBox(
                width: 680,
                height: height,
                // Landscape keyboards may leave less room than the search
                // header. Keep every control reachable instead of overflowing.
                child: SingleChildScrollView(
                  child:
                      SizedBox(height: math.max(208.0, height), child: search),
                ),
              ),
            ),
          );
        }),
      ),
    ),
  );
}

/// Independent book search; keeps the existing reader search/highlight engine.
class BookSearch extends ConsumerStatefulWidget {
  const BookSearch(
      {super.key,
      required this.onSearch,
      required this.onClear,
      required this.onNavigate,
      required this.onClose});
  final ValueChanged<String> onSearch;
  final VoidCallback onClear;
  final ValueChanged<String> onNavigate;
  final VoidCallback onClose;

  @override
  ConsumerState<BookSearch> createState() => _BookSearchState();
}

class _BookSearchState extends ConsumerState<BookSearch> {
  late final TextEditingController _query;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final state = ref.read(tocSearchProvider);
    _query = TextEditingController(text: state.query ?? '');
    _scroll = ScrollController(initialScrollOffset: state.scrollOffset);
    _scroll.addListener(() {
      if (_scroll.hasClients) {
        ref.read(tocSearchProvider.notifier).updateScrollOffset(_scroll.offset);
      }
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _query.text.trim();
    if (text.isEmpty) {
      _clear();
    } else {
      if (_scroll.hasClients) _scroll.jumpTo(0);
      FocusScope.of(context).unfocus();
      widget.onSearch(text);
    }
  }

  void _clear() {
    _query.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    widget.onClear();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tocSearchProvider);
    // Streaming results/progress must not overwrite an unfinished new query.
    ref.listen(tocSearchProvider.select((value) => value.query), (_, next) {
      if (_query.text != (next ?? '')) _query.text = next ?? '';
    });
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Padding(
      // Dialog handles the keyboard inset; do not subtract it twice.
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: Text(zh ? '书内搜索' : 'Search this book',
                  style: Theme.of(context).textTheme.titleLarge)),
          IconButton(
              key: const ValueKey('book-search-close'),
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip),
        ]),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('book-search-query'),
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: zh ? '输入书内关键词' : 'Enter a keyword',
            border: const OutlineInputBorder(),
            prefixIcon: IconButton(
                onPressed: _submit,
                icon: const Icon(Icons.search),
                tooltip: L10n.of(context).contextMenuSearch),
            suffixIcon: IconButton(
                key: const ValueKey('book-search-clear'),
                onPressed: _clear,
                icon: const Icon(Icons.clear),
                tooltip: zh ? '清除搜索' : 'Clear search'),
          ),
        ),
        const SizedBox(height: 8),
        if (state.isSearching)
          LinearProgressIndicator(
              value: state.progress <= 0 ? null : state.progress.clamp(0, 1)),
        Expanded(
            child: state.results.isEmpty
                ? Center(
                    child: Text(state.isSearching
                        ? (zh ? '正在搜索…' : 'Searching…')
                        : state.isActive
                            ? (zh ? '没有找到匹配内容' : 'No matches found')
                            : (zh
                                ? '输入关键词搜索本书内容'
                                : 'Search for text within this book')))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: state.results.length,
                    itemBuilder: (context, index) => _SearchGroup(
                        key: ValueKey(
                            '${state.query}:$index:${state.results[index].cfi}'),
                        result: state.results[index],
                        onNavigate:
                            state.isNavigating ? null : widget.onNavigate),
                  )),
      ]),
    );
  }
}

class _SearchGroup extends StatelessWidget {
  const _SearchGroup(
      {super.key, required this.result, required this.onNavigate});
  final SearchResultModel result;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        title: Text(result.label),
        subtitle: Text('${result.subitems.length}'),
        children: [
          for (final item in result.subitems)
            Card(
                child: InkWell(
              onTap: onNavigate == null ? null : () => onNavigate!(item.cfi),
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text.rich(TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium,
                        children: [
                          TextSpan(text: item.pre),
                          TextSpan(
                              text: item.match,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                          TextSpan(text: item.post),
                        ])),
                  )),
            )),
        ],
      );
}
