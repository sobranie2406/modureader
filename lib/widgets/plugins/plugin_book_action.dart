import 'package:flutter/material.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/handlers/book_action_handler.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/private_library.dart';

bool isPluginBookActionAvailable(RegisteredPluginBookAction item,
    {PluginHost? host, PrivateLibrary? privateLibrary}) {
  final owner = host ?? PluginHost.executionHostFor(item.pluginId);
  final library = privateLibrary ?? PrivateLibrary.instance;
  final manifest = owner.manifestFor(item.pluginId);
  return owner.isScriptRunnable(item.pluginId) &&
      manifest != null &&
      manifest.capabilities.contains(kBookActionCapability) &&
      manifest.capabilities.contains(kLibraryPrivateCapability) &&
      manifest.contributions.any((entry) => identical(entry, item.action)) &&
      library.active &&
      library.enabled;
}

Future<bool> runPluginBookAction(BuildContext context,
    {required RegisteredPluginBookAction item,
    required Book book,
    PluginHost? host,
    PrivateLibrary? privateLibrary}) async {
  final library = privateLibrary ?? PrivateLibrary.instance;
  bool available() =>
      context.mounted &&
      !book.isDeleted &&
      isPluginBookActionAvailable(item, host: host, privateLibrary: library);
  if (!available()) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    if (item.action.command != 'privateLibrary.hide' ||
        !await library.requestUnlock(context) ||
        !available() ||
        !library.unlocked) {
      return false;
    }
    await library.setBooksPrivate([book], true);
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
