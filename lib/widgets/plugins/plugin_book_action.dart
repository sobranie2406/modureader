import 'package:flutter/material.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/handlers/book_action_handler.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_private_library_bridge.dart';
import 'package:modu_reader/service/private_library.dart';

bool isPluginBookActionAvailable(RegisteredPluginBookAction item,
    {PluginHost? host, PrivateLibrary? privateLibrary, Book? book}) {
  final owner = host ?? PluginHost.executionHostFor(item.pluginId);
  final library = privateLibrary ?? PrivateLibrary.instance;
  final manifest = owner.manifestFor(item.pluginId);
  return owner.isScriptRunnable(item.pluginId) &&
      manifest != null &&
      manifest.capabilities.contains(kBookActionCapability) &&
      manifest.capabilities.contains(kLibraryPrivateCapability) &&
      (item.action.command != 'privateLibrary.setPrivate' ||
          manifest.capabilities.contains(kLibraryPrivateControlCapability)) &&
      manifest.contributions.any((entry) => identical(entry, item.action)) &&
      library.active &&
      library.enabled &&
      (book == null ||
          (!book.isDeleted &&
              library.canRead(book) &&
              switch (item.action.when) {
                'public' => !library.isPrivate(book),
                'private' => library.isPrivate(book),
                _ => true,
              }));
}

Future<bool> runPluginBookAction(BuildContext context,
    {required RegisteredPluginBookAction item,
    required Book book,
    PluginHost? host,
    PrivateLibrary? privateLibrary,
    Future<Book> Function(int)? readBook}) async {
  final library = privateLibrary ?? PrivateLibrary.instance;
  final owner = host ?? PluginHost.executionHostFor(item.pluginId);
  final manifest = owner.manifestFor(item.pluginId);
  bool available() =>
      context.mounted &&
      !book.isDeleted &&
      identical(owner.manifestFor(item.pluginId), manifest) &&
      isPluginBookActionAvailable(item, host: owner, privateLibrary: library);
  if (!available() ||
      !isPluginBookActionAvailable(item,
          host: owner, privateLibrary: library, book: book)) {
    return false;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    if (item.action.command == 'privateLibrary.setPrivate') {
      final setting = item.action.lockAfterSetting;
      final lockAfter = setting == null
          ? item.action.lockAfter
          : (owner.configFor(item.pluginId)[setting] ??
                  manifest!.settings
                      .singleWhere((spec) => spec.key == setting)
                      .defaultValue) ==
              true;
      final bridge = PluginPrivateLibraryBridge(
          context: context,
          host: owner,
          pluginId: item.pluginId,
          isCurrent: available,
          book: book,
          library: library,
          readBook: readBook);
      try {
        await bridge.call('privateLibrary.setPrivate', {
          'bookIds': [book.id],
          'private': item.action.privateValue,
          'lockAfter': lockAfter,
        });
        return bridge.didCommit;
      } finally {
        bridge.dispose();
      }
    }
    if (item.action.command != 'privateLibrary.hide' ||
        !await library.requestUnlock(context) ||
        !available() ||
        !library.unlocked) {
      return false;
    }
    await library.setBooksPrivate([book], true, isCurrent: available);
    // Hiding must also work when the unlocked shelf is set to show all books.
    library.lock();
    return true;
  } catch (_) {
    if (context.mounted && messenger?.mounted == true) {
      messenger!.showSnackBar(SnackBar(
          content: Text(ModuStrings.text(
              context, '未能隐藏书籍，请重试', 'Could not hide the book. Try again.'))));
    }
    return false;
  }
}
