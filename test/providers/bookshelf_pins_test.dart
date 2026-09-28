import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sort_field.dart';
import 'package:anx_reader/enums/sort_order.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/bookshelf_pins.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Book book(int id, {int group = 0}) => Book.mock().copyWith(
      id: id,
      title: '$id',
      groupId: group,
      createTime: DateTime(2026, 1, id),
      updateTime: DateTime(2026, 1, id));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('pins and unpins persist across provider and preferences reload',
      () async {
    var container = ProviderContainer();
    final key = bookPinKey(book(1));
    await container.read(bookshelfPinsProvider.notifier).setPinned(key, true);
    await container
        .read(bookshelfPinsProvider.notifier)
        .setPinned(folderPinKey(8), true);
    container.dispose();
    await Prefs().prefs.reload();
    container = ProviderContainer();
    expect(container.read(bookshelfPinsProvider), {key, folderPinKey(8)});
    await container.read(bookshelfPinsProvider.notifier).setPinned(key, false);
    container.dispose();
    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    expect(reloaded.read(bookshelfPinsProvider), {folderPinKey(8)});
  });

  for (final order in SortOrderEnum.values) {
    for (final field in SortFieldEnum.values) {
      test('pins take precedence over $field / $order', () {
        Prefs().sortOrder = order;
        Prefs().sortField = field;
        final list = BookList();
        final sorted =
            list.groupBooks(list.sortBooks([book(1), book(2), book(3)]));
        final result = applyBookshelfPins(sorted, {bookPinKey(book(2))});
        expect(result.first.single.id, 2);
        expect(result.skip(1).map((g) => g.single.id),
            sorted.where((g) => g.single.id != 2).map((g) => g.single.id));
        expect(applyBookshelfPins(sorted, {}).map((g) => g.single.id),
            sorted.map((g) => g.single.id));
      });
    }
  }

  test('folders and their books pin independently, without mutating source',
      () {
    final groups = [
      [book(1)],
      [book(2, group: 8), book(3, group: 8)],
      [book(4)]
    ];
    final result =
        applyBookshelfPins(groups, {bookPinKey(book(3)), bookPinKey(book(4))});
    expect(result.map((g) => g.first.id), [4, 1, 3]);
    expect(result.last.map((b) => b.id), [3, 2]);
    expect(groups[1].first.id, 2);
    expect(applyBookshelfPins(groups, {folderPinKey(8)}).first.length, 2);
    expect(applyBookshelfPins([], {folderPinKey(8)}), isEmpty);
  });

  test('rename and file replacement keep book pin identity', () {
    final original = book(1);
    expect(
        bookPinKey(original.copyWith(
            title: 'renamed', filePath: 'new.epub', md5: 'new')),
        bookPinKey(original));
    expect(bookPinKey(original.copyWith(createTime: DateTime(2027))),
        isNot(bookPinKey(original)));
  });

  test('single-book folder uses folder pin instead of contained book pin', () {
    final single = book(2, group: 8);
    final groups = [
      [book(1)],
      [single]
    ];
    expect(applyBookshelfPins(groups, {folderPinKey(8)}).first.single.id, 2);
    expect(applyBookshelfPins(groups, {bookPinKey(single)}).first.single.id, 1);
  });

  test('local database IDs are excluded from settings backups', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(bookshelfPinsProvider.notifier)
        .setPinned(folderPinKey(1), true);
    expect(
        await Prefs().buildPrefsBackupMap(), isNot(contains(bookshelfPinsKey)));
  });
}
