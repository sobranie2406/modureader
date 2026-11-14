import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/dao/book.dart';
import 'package:modu_reader/dao/book_note.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/book_note.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/page/plugins/article_capture_page.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/widgets/reading_page/reader_popup.dart';
import 'package:path/path.dart' as p;

Future<void> runPluginAction(BuildContext context,
    {required String pluginId,
    required ScriptActionContribution action,
    String selection = '',
    String contextText = '',
    int? bookId,
    String cfi = '',
    String chapter = '',
    ValueChanged<int>? onNoteCreated,
    PluginScriptRuntime? scriptRuntime,
    PrivateLibrary? privateLibrary,
    Future<List<Book>> Function()? selectBooks}) async {
  final runtime = scriptRuntime ?? PluginScriptRuntime.instance;
  final privacy = privateLibrary ?? PrivateLibrary.instance;
  final messenger = ScaffoldMessenger.maybeOf(context);
  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  bool current() =>
      context.mounted &&
      runtime.isRunning(pluginId) &&
      runtime.host.isScriptRunnable(pluginId);
  Book? book;
  final exposedBooks = <Book>[];
  var privateDataUsed = false, contextRevoked = false;
  ModalRoute<dynamic>? resultRoute;
  NavigatorState? resultNavigator;
  bool readable() =>
      !contextRevoked &&
      (book == null || privacy.canRead(book)) &&
      (!privateDataUsed || privacy.unlocked);
  void dismissResult() {
    final route = resultRoute, navigator = resultNavigator;
    if (route == null ||
        navigator == null ||
        !navigator.mounted ||
        !route.isActive) {
      return;
    }
    try {
      navigator.removeRoute(route);
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => dismissResult());
    }
  }

  void policyChanged() {
    if (contextRevoked) return;
    if (exposedBooks.any(privacy.isPrivate)) privateDataUsed = true;
    if (!readable()) {
      contextRevoked = true;
      runtime.cancelPlugin(pluginId);
      dismissResult();
    }
  }

  privacy.addListener(policyChanged);
  try {
    if (bookId != null) {
      final selected = await bookDao.selectBookById(bookId);
      book = selected;
      if (selected.isDeleted || !privacy.canRead(selected)) {
        throw const PluginScriptFailure('permission');
      }
    }
    if (!context.mounted) return;
    messenger?.showSnackBar(SnackBar(
      content: Text(t('正在运行插件…', 'Running plugin…')),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
          label: t('取消', 'Cancel'),
          onPressed: () => runtime.cancelPlugin(pluginId)),
    ));
    final result = await runtime.run(
        pluginId: pluginId,
        action: action,
        isContextValid: readable,
        input: {
          'selection': selection,
          'context': contextText,
          if (book != null) 'book': _summary(book),
        },
        hostCall: (method, args) async {
          if (!current() || !readable()) {
            throw const PluginScriptFailure('cancelled');
          }
          switch (method) {
            case 'articles.capture':
              if (args.isNotEmpty) {
                throw const PluginScriptFailure('permission');
              }
              unawaited(showArticleCapturePage(context, pluginId: pluginId));
              return {'opened': true};
            case 'privateLibrary.open':
              if (!privacy.active) {
                throw const PluginScriptFailure('permission');
              }
              unawaited(privacy.open(context));
              return {'opened': true};
            case 'privateLibrary.lock':
              if (!privacy.active) {
                throw const PluginScriptFailure('permission');
              }
              privacy.lock();
              return {'locked': true};
            case 'library.list':
              final offset = args['offset'] ?? 0, limit = args['limit'] ?? 20;
              if (args.keys.any((key) => !{'offset', 'limit'}.contains(key)) ||
                  offset is! int ||
                  offset < 0 ||
                  offset > 10000 ||
                  limit is! int ||
                  limit < 1 ||
                  limit > 50) {
                throw const PluginScriptFailure('permission');
              }
              final books = await (selectBooks?.call() ??
                  bookDao.selectBooks(includeDeleted: false));
              if (!current() || !readable()) {
                throw const PluginScriptFailure('cancelled');
              }
              final selected = books
                  .where(privacy.canRead)
                  .skip(offset)
                  .take(limit)
                  .toList();
              exposedBooks.addAll(selected);
              if (selected.any(privacy.isPrivate)) privateDataUsed = true;
              if (!readable()) throw const PluginScriptFailure('cancelled');
              return selected.map(_summary).toList();
            case 'notes.save':
              final text = args['text'];
              if (args.length != 1 ||
                  text is! String ||
                  text.trim().isEmpty ||
                  text.length > 8000 ||
                  book == null ||
                  cfi.isEmpty ||
                  selection.trim().isEmpty) {
                throw const PluginScriptFailure('permission');
              }
              final confirmed = await showDialog<bool>(
                  context: context,
                  barrierColor: Colors.transparent,
                  builder: (dialog) => AlertDialog(
                        title: Text(t('保存为笔记？', 'Save as a note?')),
                        content:
                            SingleChildScrollView(child: SelectableText(text)),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dialog, false),
                              child: Text(t('取消', 'Cancel'))),
                          FilledButton(
                              onPressed: () => Navigator.pop(dialog, true),
                              child: Text(t('保存', 'Save'))),
                        ],
                      ));
              if (confirmed != true) return {'saved': false};
              if (!current() || !privacy.canRead(book!)) {
                throw const PluginScriptFailure('cancelled');
              }
              final notes =
                  await bookNoteDao.selectBookNoteByCfiAndBookId(cfi, book.id);
              if (!current() || !privacy.canRead(book!)) {
                throw const PluginScriptFailure('cancelled');
              }
              final existing = notes.isEmpty ? null : notes.last;
              final now = DateTime.now();
              final note = BookNote(
                  id: existing?.id,
                  bookId: book.id,
                  content: existing?.content ?? selection,
                  cfi: cfi,
                  chapter: existing?.chapter ?? chapter,
                  type: existing?.type ?? Prefs().annotationType,
                  color: existing?.color ?? Prefs().annotationColor,
                  readerNote: [
                    if (existing?.readerNote?.trim().isNotEmpty == true)
                      existing!.readerNote!,
                    text.trim()
                  ].join('\n\n'),
                  createTime: existing?.createTime ?? now,
                  updateTime: now);
              if (existing != null) note.inheritVersion(existing);
              final id = await bookNoteDao.save(note);
              onNoteCreated?.call(id);
              return {'saved': true, 'id': id};
          }
          throw const PluginScriptFailure('permission');
        });
    messenger?.hideCurrentSnackBar();
    if (!context.mounted || !readable()) return;
    final text = result['text'] as String? ?? '';
    if (text.isEmpty) return;
    final title = result['title'] as String? ??
        action.name.resolve(Localizations.localeOf(context).toLanguageTag());
    await showReaderPopup(context,
        dimContent: book != null,
        allowWindowAdjustment: book != null,
        compactChrome: true, builder: (popup) {
      resultRoute = ModalRoute.of(popup);
      resultNavigator = Navigator.of(popup);
      if (!readable()) {
        WidgetsBinding.instance.addPostFrameCallback((_) => dismissResult());
      }
      return AnimatedBuilder(
          animation: privacy,
          builder: (_, __) => !readable()
              ? const SizedBox.shrink()
              : Column(children: [
                  ListTile(
                      title: Text(title),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            tooltip: t('复制', 'Copy'),
                            icon: const Icon(Icons.copy_outlined),
                            onPressed: () => readable()
                                ? Clipboard.setData(ClipboardData(text: text))
                                : null),
                        IconButton(
                            tooltip: t('关闭', 'Close'),
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(popup)),
                      ])),
                  Expanded(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(text))),
                ]));
    });
  } catch (error) {
    messenger?.hideCurrentSnackBar();
    if (!context.mounted) return;
    final code = error is PluginScriptFailure ? error.code : 'execution';
    final message = switch (code) {
      'cancelled' => t('插件任务已取消。', 'Plugin task cancelled.'),
      'busy' => t('插件正在运行，请稍后再试。', 'A plugin is running. Try again shortly.'),
      'timeout' => t('插件运行超时，已停止。', 'Plugin timed out and was stopped.'),
      'permission' =>
        t('插件没有此操作的权限。', 'This plugin cannot perform that action.'),
      'size' ||
      'result' =>
        t('插件内容过大或结果无效。', 'Plugin input or result is invalid or too large.'),
      _ => t('插件未能运行，请检查插件是否已启用。',
          'Could not run the plugin. Check that it is enabled.'),
    };
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  } finally {
    privacy.removeListener(policyChanged);
  }
}

Map<String, Object?> _summary(Book book) => {
      'id': book.id,
      'title': book.title,
      'author': book.author,
      'format': p.extension(book.filePath).replaceFirst('.', '').toLowerCase()
    };
