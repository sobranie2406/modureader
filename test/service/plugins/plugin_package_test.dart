import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_package.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'plugin_test_utils.dart';

void main() {
  late Directory temp;
  late PluginPaths paths;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('modu_plugin_pkg_');
    paths = PluginPaths(rootPath: p.join(temp.path, 'plugins'));
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  PluginPackageReader reader() => PluginPackageReader(paths: paths);

  test('extracts a valid package into staging with a sha256 digest', () async {
    final file = await writePluginZip(temp, samplePackageFiles());
    final package = await reader().read(file);
    expect(package.manifest.id, 'com.example.prompt-pack');
    expect(package.sha256, hasLength(64));
    expect(await package.staging.exists(), isTrue);
    expect(await File(p.join(package.staging.path, 'README.md')).readAsString(),
        contains('Example prompt pack'));
    expect(package.warnings, isEmpty);

    await package.dispose();
    expect(await package.staging.exists(), isFalse);
  });

  test('rejects a package without manifest.json', () async {
    final file = await writePluginZip(temp, {'README.md': 'hi'});
    expect(
      () => reader().read(file),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.missingManifest)),
    );
  });

  test('rejects more than the allowed number of entries', () async {
    final files = <String, String>{
      'manifest.json': manifestJson(),
      for (var i = 0; i < PluginLimits.maxEntries; i++) 'assets/$i.txt': '$i',
    };
    final file = await writePluginZip(temp, files);
    expect(
      () => reader().read(file),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.tooManyEntries)),
    );
  });

  test('rejects zip bombs by compression ratio before extracting', () async {
    final file = await writePluginZip(
        temp,
        {
          ...samplePackageFiles(),
          'assets/bomb.txt': '0' * (1024 * 1024),
        },
        level: Deflate.BEST_COMPRESSION);
    expect(
      () => reader().read(file),
      throwsA(isA<PluginInstallError>().having((error) => error.code, 'code',
          PluginErrorCode.suspiciousCompressionRatio)),
    );
  });

  test('rejects a file larger than the per-file limit', () async {
    final file = await writePluginZip(temp, {
      ...samplePackageFiles(),
      'assets/large.bin': 'x' * (PluginLimits.maxFileBytes + 1),
    });
    expect(
      () => reader().read(file),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.packageTooLarge)),
    );
  });

  test('actual inflate output is bounded even with a forged size header',
      () async {
    final file = await writePluginZip(temp, {
      ...samplePackageFiles(),
      'assets/bomb.txt': 'x' * (PluginLimits.maxFileBytes * 2),
    });
    final bytes = await file.readAsBytes();
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length - 46; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014b50 &&
          data.getUint32(i + 24, Endian.little) > PluginLimits.maxFileBytes) {
        data.setUint32(i + 24, 16, Endian.little);
      }
    }
    await file.writeAsBytes(bytes);
    await expectLater(
        reader().read(file),
        throwsA(isA<PluginInstallError>()
            .having((e) => e.code, 'code', PluginErrorCode.packageTooLarge)));
    expect(await paths.staging.list().toList(), isEmpty);
  });

  test('rejects CRC corruption without keeping staging files', () async {
    final file = await writePluginZip(temp, samplePackageFiles());
    final bytes = await file.readAsBytes();
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length - 46; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014b50) {
        data.setUint32(i + 16, 0, Endian.little);
        break;
      }
    }
    await file.writeAsBytes(bytes);
    await expectLater(
        reader().read(file),
        throwsA(isA<PluginInstallError>()
            .having((e) => e.code, 'code', PluginErrorCode.invalidPackage)));
    expect(await paths.staging.list().toList(), isEmpty);
  });

  test('rejects traversal, absolute, empty-segment and colon paths', () async {
    for (final unsafe in [
      '../evil.txt',
      '/evil.txt',
      'a//b.txt',
      'assets/a:b.txt',
    ]) {
      final file = await writePluginZip(temp, {
        ...samplePackageFiles(),
        unsafe: 'x',
      });
      expect(
        () => reader().read(file),
        throwsA(isA<PluginInstallError>().having(
            (error) => error.code, 'code', PluginErrorCode.invalidPath)),
        reason: unsafe,
      );
    }
  });

  test('normalises a backslash entry into a contained path', () async {
    // The archive package rewrites `\` to `/` while decoding, so the reader
    // never sees a raw backslash. The resulting path still stays inside the
    // package root; verify that and that nothing escapes staging.
    final file = await writePluginZip(temp, {
      ...samplePackageFiles(),
      'assets\\evil.txt': 'x',
    });
    final package = await reader().read(file);
    addTearDown(package.dispose);
    expect(
        await File(p.join(package.staging.path, 'assets', 'evil.txt')).exists(),
        isTrue);
  });

  test('rejects an oversized manifest', () async {
    final file = await writePluginZip(temp, {
      'manifest.json': ' ' * (PluginLimits.maxManifestBytes + 1),
    });
    expect(
      () => reader().read(file),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.manifestTooLarge)),
    );
  });

  test('rejects non-zip content', () async {
    final file = File(p.join(temp.path, 'bad.moduplugin'));
    await file.writeAsBytes(utf8.encode('not a zip'));
    expect(
      () => reader().read(file),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.invalidPackage)),
    );
  });

  test('rejects unsupported capability at package level', () async {
    final file = await writePluginZip(
        temp,
        samplePackageFiles(
            manifest: manifestJson(capabilities: ['script:run'])));
    expect(
      () => reader().read(file),
      throwsA(isA<PluginInstallError>().having((error) => error.code, 'code',
          PluginErrorCode.capabilityUnavailable)),
    );
  });
}
