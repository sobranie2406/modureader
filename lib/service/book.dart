import 'dart:io';
import 'dart:async';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/theme.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/current_reading_state.dart';
import 'package:anx_reader/page/home_page.dart';
import 'package:anx_reader/page/iap_page.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/chapter_content_bridge.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/iap.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/toc_search.dart';
import 'package:anx_reader/service/convert_to_epub/txt/convert_from_txt.dart';
import 'package:anx_reader/service/md5_service.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/utils/webView/anx_headless_webview.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/utils/import_book.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/webView/gererate_url.dart';
import 'package:anx_reader/utils/webView/webview_console_message.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import 'book_player/book_player_server.dart';

final allowBookExtensions = ["epub", "mobi", "azw3", "fb2", "txt", "pdf"];

/// import book list and **delete file**
void importBookList(List<File> fileList, BuildContext context, WidgetRef ref) {
  AnxLog.info('importBook fileList: ${fileList.toString()}');

  List<File> supportedFiles = fileList.where((file) {
    return allowBookExtensions
        .contains(file.path.split('.').last.toLowerCase());
  }).toList();

  List<File> unsupportedFiles = fileList.where((file) {
    return !allowBookExtensions
        .contains(file.path.split('.').last.toLowerCase());
  }).toList();

  _checkDuplicatesAndShowDialog(
    supportedFiles,
    unsupportedFiles,
    fileList,
    context,
    ref,
  );
}

void _checkDuplicatesAndShowDialog(
    List<File> supportedFiles,
    List<File> unsupportedFiles,
    List<File> fileList,
    BuildContext context,
    WidgetRef ref) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(L10n.of(context).md5Calculating),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(L10n.of(context).md5Calculating),
        ],
      ),
    ),
  );

  try {
    final filePaths = supportedFiles.map((f) => f.path).toList();
    final checkResults = await MD5Service.checkImportFiles(filePaths);

    Navigator.of(context).pop();

    List<File> duplicateFiles = [];
    List<File> uniqueFiles = [];
    Map<String, Book> duplicateInfo = {};

    for (int i = 0; i < supportedFiles.length; i++) {
      final file = supportedFiles[i];
      final result = checkResults[i];

      if (result.isDuplicate && result.duplicateBook != null) {
        duplicateFiles.add(file);
        duplicateInfo[file.path] = result.duplicateBook!;
      } else {
        uniqueFiles.add(file);
      }
    }

    _showImportDialog(
      uniqueFiles,
      duplicateFiles,
      duplicateInfo,
      unsupportedFiles,
      fileList,
      ref,
    );
  } catch (e) {
    Navigator.of(navigatorKey.currentContext!).pop();
    AnxLog.severe('MD5 check failed: $e');
    _showImportDialog(
      supportedFiles,
      [],
      {},
      unsupportedFiles,
      fileList,
      ref,
    );
  }
}

void _showImportDialog(
  List<File> uniqueFiles,
  List<File> duplicateFiles,
  Map<String, Book> duplicateInfo,
  List<File> unsupportedFiles,
  List<File> fileList,
  WidgetRef ref,
) {
  // delete unsupported files
  for (var file in unsupportedFiles) {
    file.deleteSync();
  }

  BuildContext context = navigatorKey.currentContext!;

  Widget bookItem(
    String filePath,
    Widget icon, {
    bool isDuplicate = false,
    String? duplicateTitle,
    String? errorMessage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: icon,
            ),
            Expanded(
              child: Text(
                path.basename(filePath),
                style: TextStyle(
                  fontWeight: FontWeight.w300,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (errorMessage != null)
              IconButton(
                icon: const Icon(Icons.info_outline, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(L10n.of(context).commonError),
                      content: SelectableText(errorMessage),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(L10n.of(context).commonOk),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
        if (isDuplicate && duplicateTitle != null)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 2),
            child: Text(
              L10n.of(context).duplicateOf(duplicateTitle),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 2),
            child: Text(
              'Error: ${errorMessage.length > 50 ? "${errorMessage.substring(0, 50)}..." : errorMessage}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
              ),
            ),
          ),
      ],
    );
  }

  final supportedFiles = [...uniqueFiles, ...duplicateFiles];
  bool skipDuplicates = true;

  showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        String currentHandlingFile = '';
        bool running = false;
        final succeeded = <String>{};
        List<String> errorFiles = [];
        bool finished = false;
        Map<String, String> errorMessages = {};

        return StatefulBuilder(builder: (context, setState) {
          return PopScope(
              canPop: !running,
              child: AlertDialog(
                title: Text(
                    L10n.of(context).importNBooksSelected(fileList.length)),
                contentPadding: const EdgeInsets.all(16),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L10n.of(context)
                          .importSupportTypes(allowBookExtensions.join(' / '))),

                      const SizedBox(height: 10),

                      // show unique files
                      for (var file in uniqueFiles)
                        file.path == currentHandlingFile
                            ? bookItem(
                                file.path,
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  width: 20,
                                  height: 20,
                                  child: const CircularProgressIndicator(),
                                ))
                            : bookItem(
                                file.path,
                                errorFiles.contains(file.path)
                                    ? const Icon(Icons.error)
                                    : Icon(succeeded.contains(file.path)
                                        ? Icons.done
                                        : Icons.schedule),
                                errorMessage: errorFiles.contains(file.path)
                                    ? errorMessages[file.path]
                                    : null,
                              ),

                      // show unsupported files
                      if (unsupportedFiles.isNotEmpty) ...[
                        Divider(),
                        SizedBox(height: 10),
                        Text(L10n.of(context)
                            .importNBooksNotSupport(unsupportedFiles.length))
                      ],
                      for (var file in unsupportedFiles)
                        bookItem(file.path, const Icon(Icons.error)),

                      // show duplicate files
                      if (duplicateFiles.isNotEmpty) ...[
                        Divider(),
                        const SizedBox(height: 10),
                        Text(L10n.of(context).duplicateFile),
                      ],
                      for (var file in duplicateFiles)
                        if (skipDuplicates)
                          bookItem(
                            file.path,
                            const Icon(Icons.double_arrow_rounded),
                            isDuplicate: true,
                            duplicateTitle: duplicateInfo[file.path]?.title,
                          )
                        else
                          file.path == currentHandlingFile
                              ? bookItem(
                                  file.path,
                                  Container(
                                    padding: const EdgeInsets.all(3),
                                    width: 20,
                                    height: 20,
                                    child: const CircularProgressIndicator(),
                                  ),
                                  isDuplicate: true,
                                  duplicateTitle:
                                      duplicateInfo[file.path]?.title,
                                )
                              : bookItem(
                                  file.path,
                                  errorFiles.contains(file.path)
                                      ? const Icon(Icons.error)
                                      : Icon(succeeded.contains(file.path)
                                          ? Icons.done
                                          : Icons.schedule),
                                  isDuplicate: true,
                                  duplicateTitle:
                                      duplicateInfo[file.path]?.title,
                                  errorMessage: errorFiles.contains(file.path)
                                      ? errorMessages[file.path]
                                      : null,
                                ),

                      // select skip duplicates
                      if (duplicateFiles.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Checkbox(
                              value: skipDuplicates,
                              onChanged: running || finished
                                  ? null
                                  : (value) {
                                      setState(() {
                                        skipDuplicates = value ?? true;
                                      });
                                    },
                            ),
                            Expanded(
                              child: Text(L10n.of(context).skipDuplicateFiles),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: running
                        ? null
                        : () {
                            Navigator.pop(context);
                            for (var file in supportedFiles) {
                              if (file.existsSync()) file.deleteSync();
                            }
                          },
                    child: Text(L10n.of(context).commonCancel),
                  ),
                  if (uniqueFiles.isNotEmpty ||
                      (duplicateFiles.isNotEmpty && !skipDuplicates))
                    TextButton(
                        onPressed: running
                            ? null
                            : () async {
                                if (finished) {
                                  Navigator.of(context).pop('dialog');
                                  return;
                                }
                                setState(() => running = true);

                                List<File> filesToImport = [...uniqueFiles];
                                if (!skipDuplicates) {
                                  filesToImport.addAll(duplicateFiles);
                                }

                                for (var file in filesToImport) {
                                  AnxToast.show(path.basename(file.path));
                                  setState(() {
                                    currentHandlingFile = file.path;
                                  });
                                  try {
                                    await importBook(file, ref);
                                    succeeded.add(file.path);
                                  } catch (e, stackTrace) {
                                    AnxLog.severe(
                                        'Failed to import ${file.path}: $e');
                                    AnxLog.severe('Stack trace: $stackTrace');
                                    setState(() {
                                      errorFiles.add(file.path);
                                      errorMessages[file.path] = e.toString();
                                    });
                                  } finally {
                                    if (context.mounted) {
                                      setState(() => currentHandlingFile = '');
                                    }
                                  }
                                }

                                // dumplicateFiles will be deleted if skipDuplicates is true
                                // if skipDuplicates is false, they will be imported
                                // and then deleted in the importBook function
                                if (skipDuplicates) {
                                  for (var file in duplicateFiles) {
                                    if (file.existsSync()) file.deleteSync();
                                  }
                                }

                                setState(() {
                                  finished = true;
                                  running = false;
                                });
                                if (succeeded.isNotEmpty) {
                                  ref.read(syncProvider.notifier).syncData(
                                      SyncDirection.upload, ref,
                                      trigger: SyncTrigger.auto);
                                }
                              },
                        child: Text(finished
                            ? L10n.of(context).commonOk
                            : L10n.of(context).importImportNBooks(uniqueFiles
                                    .length +
                                (skipDuplicates ? 0 : duplicateFiles.length) -
                                errorFiles.length))),
                ],
              ));
        });
      });
}

Future<void> importBook(File file, WidgetRef ref) async {
  String? md5 = await MD5Service.calculateFileMd5(file.path);

  if (file.path.split('.').last.toLowerCase() == 'txt') {
    final tempFile = await convertFromTxt(file);
    file.deleteSync();
    file = tempFile;
  }

  await getBookMetadata(file, md5: md5, ref: ref);
  if (await file.exists()) await file.delete();
  ref.read(bookListProvider.notifier).refresh();
}

Future<void> pushToReadingPage(
  WidgetRef ref,
  BuildContext context,
  Book book, {
  String? cfi,
  String? heroTag,
}) async {
  if (book.isDeleted) {
    AnxToast.show(L10n.of(context).bookDeleted);
    return;
  }

  if (!File(book.fileFullPath).existsSync()) {
    ref.read(syncProvider.notifier).downloadBook(book);
    return;
  }

  if (EnvVar.enableInAppPurchase) {
    final iapAsync = ref.read(iapProvider);
    final isFeatureAvailable = iapAsync.maybeWhen(
      data: (state) => state.isFeatureAvailable,
      orElse: () => ref.read(iapProvider.notifier).cachedFeatureAvailable(),
    );

    if (!isFeatureAvailable) {
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (context) => const IAPPage(),
        ),
      );
      return;
    }
  }
  ref.read(aiChatProvider(AiChatScope.reader).notifier).clear();
  final initialThemes = await themeDao.selectThemes();
  ref.read(currentReadingProvider.notifier).start(
        CurrentReadingState(
          book: book,
          cfi: cfi,
        ),
      );

  final currentReading = ref.read(currentReadingProvider.notifier);
  final chapterContentBridge = ref.read(chapterContentBridgeProvider.notifier);
  final tocSearch = ref.read(tocSearchProvider.notifier);

  await Navigator.push(
    navigatorKey.currentContext!,
    CupertinoPageRoute(
      builder: (c) => ReadingPage(
        key: readingPageKey,
        book: book,
        cfi: cfi,
        initialThemes: initialThemes,
        heroTag: heroTag,
      ),
    ),
  ).then((_) {
    AnxLog.info('ReadingPage: poped: ${book.title}');
    currentReading.finish();
    chapterContentBridge.state = null;
    tocSearch.clear();
    AnxLog.info('Pop successfully ReadingPage: ${book.title}');
  });
}

void updateBookRating(Book book, double rating) {
  book.rating = rating;
  bookDao.updateBook(book);
}

Future<void> resetBookCover(Book book) async {
  File file = File(book.fileFullPath);
  await getBookMetadata(file, book: book, md5: book.md5, coverOnly: true);
}

Future<void> saveBook(
  File file,
  String title,
  String author,
  String description,
  String? md5,
  String cover, {
  Book? provideBook,
}) async {
  // Extract original filename (without extension)
  final fileNameWithoutExt = path.basenameWithoutExtension(file.path);

  // Use original filename if title is invalid
  final effectiveTitle =
      (title == 'Unknown' || title.trim().isEmpty) ? fileNameWithoutExt : title;

  final newBookName =
      '${effectiveTitle.length > 20 ? effectiveTitle.substring(0, 20) : effectiveTitle}-${DateTime.now().microsecondsSinceEpoch}'
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .trim();

  final extension = file.path.split('.').last;

  final dbFilePath = 'file/$newBookName.$extension';
  final filePath = getBasePath(dbFilePath);
  String dbCoverPath = 'cover/$newBookName';
  // final coverPath = getBasePath(dbCoverPath);

  // Preserve the source until both file and database writes have succeeded.
  await file.copy(filePath);
  dbCoverPath = cover.isEmpty ? '' : await saveImageToLocal(cover, dbCoverPath);
  if (md5 != null) {
    provideBook ??= await bookDao.getBookByMd5(md5);
  }

  Book book = Book(
      id: provideBook != null ? provideBook.id : -1,
      title: provideBook?.title ?? effectiveTitle,
      coverPath: dbCoverPath,
      filePath: dbFilePath,
      lastReadPosition: provideBook?.lastReadPosition ?? '',
      readingPercentage: provideBook?.readingPercentage ?? 0,
      author: provideBook?.author ?? author,
      isDeleted: false,
      rating: provideBook?.rating ?? 0.0,
      md5: md5,
      createTime: provideBook?.createTime ?? DateTime.now(),
      updateTime: DateTime.now());

  try {
    book.id = await bookDao.insertBook(book);
  } catch (_) {
    // Only remove newly created staging artifacts; never the imported source.
    final copied = File(filePath);
    if (await copied.exists()) await copied.delete();
    if (dbCoverPath.isNotEmpty) {
      final savedCover = File(getBasePath(dbCoverPath));
      if (await savedCover.exists()) await savedCover.delete();
    }
    rethrow;
  }
  AnxToast.show(L10n.of(navigatorKey.currentContext!).serviceImportSuccess);
  final queued = enqueueImportedBookForAutomaticIndexing(
    book: book,
    vectorModelEnabled: Prefs().vectorModelEnabled,
    autoVectorizeOnImport: Prefs().autoVectorizeOnImport,
  );
  if (queued) {
    AnxLog.info('Imported book ${book.id} joined the vectorization queue');
  }
  return;
}

Future<void> getBookMetadata(
  File file, {
  Book? book,
  String? md5,
  WidgetRef? ref,
  bool coverOnly = false,
}) async {
  final serverFileName = Server().setTempFile(file);
  final result = Completer<Map<String, dynamic>>();
  void fail(Object error) {
    if (!result.isCompleted) result.completeError(error);
  }

  // Attach the error listener before the native WebView starts calling back.
  final metadataFuture = result.future.timeout(const Duration(seconds: 45));
  unawaited(
      metadataFuture.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  final webview = AnxHeadlessWebView(
    webViewEnvironment: webViewEnvironment,
    initialUrlRequest: URLRequest(
        url: WebUri(generateUrl(
      'http://127.0.0.1:${Server().port}/$serverFileName',
      '',
      importing: true,
    ))),
    onWebViewCreated: (controller) {
      controller.addJavaScriptHandler(
          handlerName: 'onMetadata',
          callback: (args) {
            if (result.isCompleted) return;
            try {
              result.complete(Map<String, dynamic>.from(args.single as Map));
            } catch (error) {
              fail(error);
            }
          });
      controller.addJavaScriptHandler(
          handlerName: 'onImportError',
          callback: (args) {
            final error = args.isEmpty ? null : args.first;
            final password =
                error is Map && error['name'] == 'PasswordException';
            fail(FormatException(password
                ? '此 PDF 需要密码，暂不支持加密 PDF。请先解密后导入。'
                : '书籍解析失败：${error is Map ? error['message'] : error}'));
          });
    },
    onLoadError: (_, __, ___, message) => fail(StateError('导入页面加载失败：$message')),
    onLoadHttpError: (_, __, status, ___) =>
        fail(StateError('导入页面请求失败：HTTP $status')),
    onConsoleMessage: (controller, consoleMessage) {
      if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR) {
        AnxLog.warning('Import WebView: ${consoleMessage.message}');
      }
      webviewConsoleMessage(controller, consoleMessage);
    },
  );

  try {
    await webview.run();
    final metadata = await metadataFuture;
    if (coverOnly) {
      final cover = metadata['cover']?.toString() ?? '';
      if (book == null || cover.isEmpty) {
        throw const FormatException('书籍没有可恢复的封面');
      }
      final coverPath = await saveImageToLocal(
          cover, 'cover/${book.id}-${DateTime.now().microsecondsSinceEpoch}');
      await bookDao.updateBook(book.copyWith(coverPath: coverPath));
      return;
    }
    final rawAuthor = metadata['author'];
    final author = rawAuthor is List
        ? rawAuthor
            .map((a) => a is Map ? a['name'] : a)
            .whereType<Object>()
            .join(', ')
        : rawAuthor?.toString() ?? 'Unknown';
    await saveBook(
        file,
        metadata['title']?.toString() ?? 'Unknown',
        author,
        metadata['description']?.toString() ?? '',
        md5,
        metadata['cover']?.toString() ?? '',
        provideBook: book);
    ref?.read(bookListProvider.notifier).refresh();
  } finally {
    if (!result.isCompleted) fail(StateError('导入已结束'));
    await webview.dispose();
    Server().releaseTempFile(serverFileName);
  }
}
