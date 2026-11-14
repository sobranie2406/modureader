import 'package:modu_reader/service/ai/ai_history.dart';
import 'package:modu_reader/providers/private_library.dart';
import 'package:modu_reader/dao/book.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final aiHistoryProvider = StateNotifierProvider<AiHistoryNotifier,
    AsyncValue<List<AiChatHistoryEntry>>>((ref) {
  ref.watch(privateLibraryRevisionProvider);
  return AiHistoryNotifier();
});

class AiHistoryNotifier
    extends StateNotifier<AsyncValue<List<AiChatHistoryEntry>>> {
  AiHistoryNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final history = await AiHistoryStore.readHistory();
      if (PrivateLibrary.instance.corrupt) {
        if (mounted) state = const AsyncValue.data([]);
        return;
      }
      final accessible = history
          .where((e) => PrivateLibrary.instance
              .canReadHistory(e.id, unscoped: e.readingRequest?.bookId == null))
          .toList();
      if (!PrivateLibrary.instance.hasPrivateBooks ||
          !PrivateLibrary.instance.enabled) {
        if (mounted) state = AsyncValue.data(accessible);
        return;
      }
      final ids = accessible
          .map((e) => e.readingRequest?.bookId)
          .whereType<int>()
          .toSet()
          .toList();
      final books = ids.isEmpty
          ? const []
          : await bookDao.selectBooksByIds(ids, includeDeleted: true);
      final hidden = books
          .where((b) => !PrivateLibrary.instance.isVisible(b))
          .map((b) => b.id)
          .toSet();
      if (mounted) {
        state = AsyncValue.data(accessible
            .where((e) => !hidden.contains(e.readingRequest?.bookId))
            .toList());
      }
    } catch (error, stack) {
      if (mounted) state = AsyncValue.error(error, stack);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _load();
  }

  Future<void> upsert(AiChatHistoryEntry entry) async {
    await AiHistoryStore.upsertEntry(entry);
    await _load();
  }

  Future<void> remove(String id) async {
    await AiHistoryStore.removeEntry(id);
    await _load();
  }

  Future<void> clear() async {
    await AiHistoryStore.clear();
    state = const AsyncValue.data([]);
  }

  Future<void> clearScope(String scope) async {
    await AiHistoryStore.clearScope(scope);
    await _load();
  }

  Future<void> clearHistoryKey(String key) async {
    await AiHistoryStore.clearHistoryKey(key);
    await _load();
  }

  AiChatHistoryEntry? findById(String id) {
    return state.maybeWhen(
      data: (entries) {
        for (final entry in entries) {
          if (entry.id == id) {
            return entry;
          }
        }
        return null;
      },
      orElse: () => null,
    );
  }
}
