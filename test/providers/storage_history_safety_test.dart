import 'dart:io';
import 'dart:convert';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/providers/storage_info.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:langchain_core/chat_models.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/data';
  @override
  Future<String?> getApplicationSupportPath() async => '$root/data';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'cache cleanup preserves migrated history and accounts for nested durable files',
      () async {
    final root = await Directory.systemTemp.createTemp('modu-storage-test-');
    final previousPaths = PathProviderPlatform.instance;
    final previousDocumentPath = documentPath;
    PathProviderPlatform.instance = _Paths(root.path);
    documentPath = '${root.path}/data';
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final container = ProviderContainer();
    addTearDown(() async {
      container.dispose();
      documentPath = previousDocumentPath;
      PathProviderPlatform.instance = previousPaths;
      await root.delete(recursive: true);
    });
    final cache = await Directory('${root.path}/cache').create();
    final history = AiChatHistoryEntry(
        id: 'fixture',
        scope: 'reader',
        serviceId: 'fake',
        model: 'fake',
        createdAt: 1,
        updatedAt: 1,
        messages: [ChatMessage.humanText('saved')],
        completed: true);
    await File('${cache.path}/ai_history.json')
        .writeAsString(jsonEncode([history.toJson()]));
    await File('${cache.path}/temporary').writeAsString('disposable');
    for (final relative in [
      'models/embeddings/model.onnx',
      'knowledge/1.json',
      'bgimg/image.png',
      'file/book.epub'
    ]) {
      final file = File('$documentPath/$relative');
      await file.parent.create(recursive: true);
      await file.writeAsString('1234567890');
    }
    final initialInfo = await container.read(storageInfoProvider.future);
    expect(initialInfo.aiHistorySize, greaterThan(0));
    expect(await File('${cache.path}/ai_history.json').exists(), isTrue);
    expect(await File('${cache.path}/temporary').exists(), isTrue);
    expect(await container.read(storageInfoProvider.notifier).clearCache(),
        isTrue);
    expect(await File('${cache.path}/temporary').exists(), isFalse);
    expect((await AiHistoryStore.readHistory()).single.id, 'fixture');
    final info = await container.read(storageInfoProvider.future);
    expect(info.modelSize, 10);
    expect(info.indexSize, 10);
    expect(info.backgroundSize, 10);
    expect(info.booksSize, 10);
    expect(info.aiHistorySize, greaterThan(0));
  });
}
