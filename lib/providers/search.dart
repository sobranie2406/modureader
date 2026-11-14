import 'package:modu_reader/providers/private_library.dart';
import 'package:modu_reader/dao/search_repository.dart';
import 'package:modu_reader/models/search_note_group.dart';
import 'package:modu_reader/models/search_result_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return const SearchRepository();
});

final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Which sources the shelf search queries. Both default to on, matching the
/// old "search books or notes" behavior; notes always cover excerpts,
/// comments and chapter names.
class SearchScope {
  const SearchScope({this.books = true, this.notes = true});

  final bool books;
  final bool notes;

  bool get isEmpty => !books && !notes;

  SearchScope copyWith({bool? books, bool? notes}) => SearchScope(
        books: books ?? this.books,
        notes: notes ?? this.notes,
      );
}

final searchScopeProvider =
    StateProvider.autoDispose<SearchScope>((ref) => const SearchScope());

final searchResultProvider = FutureProvider.autoDispose
    .family<SearchResultData, int?>((ref, bookId) async {
  ref.watch(privateLibraryRevisionProvider);
  final query = ref.watch(searchQueryProvider);
  final repository = ref.watch(searchRepositoryProvider);
  final trimmed = query.trim();

  if (trimmed.isEmpty) {
    return SearchResultData.empty;
  }

  // Searching inside one book only ever looks at its notes.
  final scope = bookId != null
      ? const SearchScope(books: false)
      : ref.watch(searchScopeProvider);
  if (scope.isEmpty) {
    return SearchResultData.empty;
  }

  final result = await repository.search(
    trimmed,
    bookId: bookId,
    includeBooks: scope.books,
    includeNotes: scope.notes,
  );
  final noteGroups = result.noteGroups
      .map(
        (entry) => SearchNoteGroup(
          book: entry.book,
          notes: entry.notes,
        ),
      )
      .toList(growable: false);

  return SearchResultData(
    books: result.books,
    noteGroups: noteGroups,
  );
});
