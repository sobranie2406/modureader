import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:crypto/crypto.dart';

/// Book-local model references only. Credentials remain in vector settings.
/// A file identity avoids binding restored preferences to reused database IDs.
class BookEmbeddingPreferences {
  static String keyFor(Book book) {
    final identity = book.filePath.isNotEmpty
        ? book.filePath.replaceAll('\\', '/')
        : '${book.id}:${book.createTime.toIso8601String()}';
    return 'bookEmbeddingModel_${sha256.convert(utf8.encode(identity))}';
  }

  static String? choiceFor(Book book) => Prefs().prefs.getString(keyFor(book));

  static bool isValid(String choice) =>
      choice == 'remote' ||
      LocalEmbeddingModels.all.any((model) => choice == 'local:${model.id}');

  static Future<void> save(Book book, String? choice) async {
    if (choice != null && !isValid(choice)) {
      throw ArgumentError.value(choice, 'choice', 'Unknown vector model');
    }
    final prefs = Prefs();
    final success = choice == null
        ? await prefs.prefs.remove(keyFor(book))
        : await prefs.prefs.setString(keyFor(book), choice);
    if (!success) throw StateError('无法保存本书向量模型');
    prefs.notifyExternalChange();
  }

  static String labelFor(Book book) {
    final choice = choiceFor(book);
    if (choice == null) return '使用默认模型';
    if (choice == 'remote') return '远程模型（设置中的接口）';
    for (final model in LocalEmbeddingModels.all) {
      if (choice == 'local:${model.id}') return model.name;
    }
    return '模型不可用，请重新选择';
  }
}
