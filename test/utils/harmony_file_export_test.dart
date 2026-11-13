import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:modu_reader/utils/harmony_file_export.dart';
import 'package:modu_reader/utils/harmony_file_share.dart';
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
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late PathProviderPlatform previousPaths;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('modu-export-test-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(harmonyFileExportChannel, null);
    PathProviderPlatform.instance = previousPaths;
    await directory.delete(recursive: true);
  });

  for (final outcome in ['success', 'cancel', 'error']) {
    test('$outcome preserves source and removes the private snapshot',
        () async {
      final original = await File('${directory.path}/original.log')
          .writeAsString('WARNING 中文日志\n');
      messenger.setMockMethodCallHandler(harmonyFileExportChannel,
          (call) async {
        expect(call.method, 'saveFile');
        final args = call.arguments as Map;
        expect(args['fileName'], '日志.txt');
        expect(args['sourcePath'], isNot(original.path));
        expect(await File(args['sourcePath']).readAsBytes(),
            await original.readAsBytes());
        if (outcome == 'error') throw PlatformException(code: 'export_failed');
        return outcome == 'cancel' ? null : 'file://docs/export/%E6%97%A5.txt';
      });
      final result =
          saveHarmonyFile(sourceFilePath: original.path, fileName: '日志.txt');
      if (outcome == 'error') {
        await expectLater(result, throwsA(isA<PlatformException>()));
      } else {
        expect(await result,
            outcome == 'cancel' ? null : 'file://docs/export/%E6%97%A5.txt');
      }
      expect(await original.readAsString(), 'WARNING 中文日志\n');
      expect(await directory.list().length, 1);
    });
  }

  test('bytes take priority, snapshots survive until native completion',
      () async {
    final completion = Completer<String?>();
    final entered = Completer<void>();
    late File snapshot;
    messenger.setMockMethodCallHandler(harmonyFileExportChannel, (call) async {
      snapshot = File((call.arguments as Map)['sourcePath']);
      expect(await snapshot.readAsString(), '测试');
      entered.complete();
      return completion.future;
    });
    final result = saveHarmonyFile(
        bytes: utf8.encode('测试'),
        sourceFilePath: '/nonexistent',
        fileName: 'export.txt');
    await entered.future;
    expect(await snapshot.exists(), isTrue);
    completion.complete('file://docs/export.txt');
    await result;
    expect(await snapshot.exists(), isFalse);
    expect(await directory.list().length, 0);
  });

  test('invalid names and absent content cannot open the picker', () async {
    messenger.setMockMethodCallHandler(harmonyFileExportChannel, (_) async {
      fail('Picker must not open');
    });
    for (final name in ['', '..', '../log.txt', 'a/b', r'a\b', 'a\x00b']) {
      await expectLater(
          saveHarmonyFile(bytes: utf8.encode('x'), fileName: name),
          throwsArgumentError);
    }
    await expectLater(
        saveHarmonyFile(fileName: 'log.txt'), throwsArgumentError);
    await expectLater(
        saveHarmonyFile(sourceFilePath: '/nonexistent', fileName: 'log.txt'),
        throwsA(isA<FileSystemException>()));
    expect(await directory.list().length, 0);
  });

  test(
      'sharing retains the named snapshot after opening and leaves source intact',
      () async {
    final original =
        await File('${directory.path}/original.epub').writeAsBytes([0, 1, 255]);
    late File snapshot;
    messenger.setMockMethodCallHandler(harmonyFileExportChannel, (call) async {
      expect(call.method, 'shareFile');
      final args = call.arguments as Map;
      expect(args['fileName'], '书_名.epub');
      snapshot = File(args['sourcePath']);
      expect(snapshot.path, isNot(original.path));
      expect(await snapshot.readAsBytes(), [0, 1, 255]);
      return null; // Sheet opened, not delivery confirmation.
    });
    await shareHarmonyFile(sourceFilePath: original.path, title: '书/名.epub');
    expect(await snapshot.exists(), isTrue);
    expect(await original.readAsBytes(), [0, 1, 255]);
    // A subsequent share must not delete the recipient's still-recent snapshot.
    final first = snapshot;
    await shareHarmonyFile(sourceFilePath: original.path, title: '书/名.epub');
    expect(await first.exists(), isTrue);
  });

  test('failed share removes its snapshot and does not alter the book',
      () async {
    final original =
        await File('${directory.path}/original.epub').writeAsString('book');
    messenger.setMockMethodCallHandler(harmonyFileExportChannel, (_) async {
      throw PlatformException(code: 'share_failed');
    });
    await expectLater(shareHarmonyFile(sourceFilePath: original.path),
        throwsA(isA<PlatformException>()));
    expect(await directory.list().length, 1);
    expect(await original.readAsString(), 'book');
    await expectLater(shareHarmonyFile(sourceFilePath: '/nonexistent'),
        throwsA(isA<FileSystemException>()));
  });
}
