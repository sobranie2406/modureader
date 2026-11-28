import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/handlers/script_action_handler.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_host_api.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:path/path.dart' as p;

Future<void> runReaderOpenPlugins({
  required Book book,
  required bool Function() isCurrent,
  required Future<PluginReadingPosition> Function() readingPosition,
  required PluginReadingPositionApplier applyReadingPosition,
  PluginScriptRuntime Function(String) resolveRuntime = PluginHost.runtimeFor,
}) async {
  final registry = PluginScriptActionRegistry.instance;
  final format = p.extension(book.filePath).replaceFirst('.', '').toLowerCase();
  final privacy = PrivateLibrary.instance;
  for (final item in registry.forSurface(PluginScriptSurface.readerOpen)) {
    final action = item.action;
    if (!action.supportsFormat(format)) continue;
    final id = item.pluginId;
    final runtime = resolveRuntime(id);
    final host = runtime.host;
    bool current() =>
        isCurrent() &&
        !book.isDeleted &&
        !privacy.corrupt &&
        !privacy.isPrivate(book) &&
        host.isScriptRunnable(id) &&
        identical(registry.byId(item.id), item) &&
        host.configFor(id)[action.enabledSetting] == true;
    if (!current()) continue;
    final api = PluginHostApi(
        pluginId: id,
        storageRoot: host.paths.dataDir(id),
        services: PluginHostServices(
            grantedPermissions: (id) async => host.grantedPermissions(id),
            reader: PluginReaderSnapshot(
                book: book,
                chapter: '',
                isCurrent: current,
                readingPosition: readingPosition,
                applyReadingPosition: applyReadingPosition)));
    try {
      await runtime.run(
          pluginId: id, action: action, hostApi: api, isContextValid: current);
    } on PluginScriptFailure {
      // The runtime logs the stage and error code. Opening the book continues.
    } catch (error) {
      AnxLog.warning('Reader-open plugin failed: ${error.runtimeType}');
    }
  }
}
