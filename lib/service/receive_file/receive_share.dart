import 'dart:async';
import 'dart:io';

import 'package:modu_reader/service/book.dart';
import 'package:modu_reader/service/receive_file/external_book_inbox.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:modu_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';

const externalFilesChannel = MethodChannel('com.modu.reader/external_files');
bool _listening = false;

/// Start before initialization so native file access and cold deliveries survive
/// storage/migration prompts. Import itself waits for the home navigator.
void listenForExternalBooks() {
  if (_listening) return;
  _listening = true;
  if (Platform.isIOS || Platform.isMacOS || AnxPlatform.isOhos) {
    externalFilesChannel.setMethodCallHandler((call) async {
      if (call.method == 'files') {
        externalBookInbox.add((call.arguments as List).cast<String>());
      } else if (call.method == 'error') {
        _reportImportError(call.arguments);
      }
    });
    externalFilesChannel.invokeListMethod<String>('ready').then((paths) {
      externalBookInbox.add(paths ?? []);
    }).catchError((Object error) {
      _reportImportError(error);
    });
  }
  if (AnxPlatform.isAndroid || AnxPlatform.isIOS) {
    final handler = ShareHandlerPlatform.instance;
    void receive(SharedMedia? media) {
      if (media == null) return;
      externalBookInbox.add([
        for (final item in media.attachments ?? <SharedAttachment?>[])
          if (item != null) item.path,
      ]);
      unawaited(
          handler.resetInitialSharedMedia().catchError(_reportImportError));
    }

    handler.sharedMediaStream.listen(receive, onError: _reportImportError);
    handler.getInitialSharedMedia().then(receive, onError: _reportImportError);
  }
}

void receiveExternalBooks(WidgetRef ref) {
  externalBookInbox.attach((paths) async {
    try {
      final entries = await externalBookEntries(paths);
      await importBooksQuietly(entries, ref);
    } catch (error) {
      _reportImportError(error);
    }
  });
}

void _reportImportError(Object? error) {
  AnxLog.warning('External book import failed: $error');
}
