import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device-local shelf layout, not transferable settings (database IDs are local).
const bookshelfPinsKey = 'bookshelfPins';

String bookPinKey(Book book) =>
    'book:${book.id}:${book.createTime.toIso8601String()}';
String folderPinKey(int groupId) => 'folder:$groupId';

final bookshelfPinsProvider =
    NotifierProvider<BookshelfPins, Set<String>>(BookshelfPins.new);

class BookshelfPins extends Notifier<Set<String>> {
  @override
  Set<String> build() =>
      Set.unmodifiable(Prefs().prefs.getStringList(bookshelfPinsKey) ?? []);

  Future<void> setPinned(String key, bool pinned) async {
    final previous = state;
    final next = {...state};
    if (pinned) {
      next.add(key);
    } else {
      next.remove(key);
    }
    final updated = Set<String>.unmodifiable(next);
    state = updated;
    try {
      if (!await Prefs().prefs.setStringList(bookshelfPinsKey, next.toList())) {
        throw StateError('Could not save bookshelf pins');
      }
    } catch (_) {
      if (identical(state, updated)) state = previous;
      rethrow;
    }
  }
}

/// Keep the existing sort within each section. Pinning a book in a folder must
/// not move the folder itself; folder and book priorities are independent.
List<List<Book>> applyBookshelfPins(List<List<Book>> groups, Set<String> pins) {
  final ordered = groups
      .map((group) => [
            ...group.where((book) => pins.contains(bookPinKey(book))),
            ...group.where((book) => !pins.contains(bookPinKey(book))),
          ])
      .toList();
  bool pinned(List<Book> group) => pins.contains(group.first.groupId == 0
      ? bookPinKey(group.first)
      : folderPinKey(group.first.groupId));
  return [
    ...ordered.where(pinned),
    ...ordered.where((group) => !pinned(group)),
  ];
}
