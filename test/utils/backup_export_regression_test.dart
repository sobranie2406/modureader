import 'dart:io';
import 'package:modu_reader/page/settings_page/sync.dart';
import 'package:modu_reader/utils/platform_utils.dart';
import 'package:modu_reader/utils/get_path/get_download_path.dart';
import 'package:modu_reader/utils/save_file_to_download.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform oldPaths;
  late List<MethodCall> permissionCalls;
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  setUp(() async {
    permissionCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (call) async {
      permissionCalls.add(call);
      return call.method == 'requestPermissions' ? <int, int>{} : 0;
    });
    root = await Directory.systemTemp.createTemp('modu-export-test-');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null);
    expect(permissionCalls, isEmpty,
        reason:
            'Path lookup and document export must not request storage access');
    PathProviderPlatform.instance = oldPaths;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_file_dialog'), null);
    await root.delete(recursive: true);
  });
  test('Android download path lookup does not request all-files access',
      () async {
    expect(await getDownloadPath(platform: AnxPlatformEnum.android),
        '/storage/emulated/0/Download');
  });
  test('ZIP worker uses explicit paths without prefs or platform channels',
      () async {
    final prefs =
        await File('${root.path}/modu_shared_prefs.json').writeAsString('{}');
    final db = await File('${root.path}/snapshot.db').writeAsString('snapshot');
    final doc = await Directory('${root.path}/library').create();
    final book =
        await File('${doc.path}/file/test.epub').create(recursive: true);
    await book.writeAsString('book');
    final zip = await compute(createZipFile, <String, dynamic>{
      'documentPath': doc.path,
      'tempPath': root.path,
      'prefsBackupFilePath': prefs.path,
      'snapshotPath': db.path,
    });
    final archive = ZipDecoder().decodeBytes(await File(zip).readAsBytes());
    expect(archive.findFile('databases/app_database.db'), isNotNull);
    expect(archive.findFile('file/test.epub'), isNotNull);
  });
  for (final outcome in ['success', 'cancel', 'error']) {
    test('Android bytes use app cache and clean up after $outcome', () async {
      String? staged;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_file_dialog'),
              (call) async {
        final args = call.arguments as Map;
        expect(args['data'], isNull);
        expect(args['fileName'], 'settings.json');
        staged = args['sourceFilePath'] as String;
        expect(await File(staged!).readAsBytes(), [1, 2, 3]);
        if (outcome == 'error') throw PlatformException(code: 'write_failed');
        return outcome == 'cancel' ? null : 'content://saved';
      });
      final result = saveFileToDownload(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'settings.json',
          platform: AnxPlatformEnum.android);
      if (outcome == 'error') {
        await expectLater(result, throwsA(isA<PlatformException>()));
      } else {
        expect(await result, outcome == 'cancel' ? null : 'content://saved');
      }
      expect(staged, isNotNull);
      expect(await File(staged!).exists(), isFalse);
    });
  }
}
