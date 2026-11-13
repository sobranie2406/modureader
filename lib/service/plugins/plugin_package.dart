import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A validated package unpacked into a staging directory. [dispose] removes
/// the staging directory; the host moves it into place on success.
class PluginPackage {
  PluginPackage({
    required this.manifest,
    required this.manifestText,
    required this.staging,
    required this.sha256,
    required this.compressedBytes,
    required this.warnings,
  });

  final PluginManifest manifest;
  final String manifestText;
  final Directory staging;
  final String sha256;
  final int compressedBytes;
  final List<String> warnings;

  Future<void> dispose() async {
    try {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    } catch (_) {
      // A leftover staging directory is removed by the next startup sweep.
    }
  }
}

/// Reads `.moduplugin` (zip) files without trusting any archive metadata.
///
/// Everything is limits-first: declared uncompressed sizes are checked before
/// decompression, paths are rejected before touching the filesystem, and the
/// manifest is parsed only after the whole package passed validation.
class PluginPackageReader {
  PluginPackageReader({
    PluginPaths? paths,
    this.allowedCapabilities = kP1SupportedCapabilities,
  }) : paths = paths ?? PluginPaths();

  final PluginPaths paths;
  final Set<String> allowedCapabilities;

  Future<PluginPackage> read(File file) async {
    if (!await file.exists()) {
      throw const PluginInstallError(
          PluginErrorCode.invalidPackage, 'The selected file does not exist.');
    }
    // Reject obviously oversized files before reading them into memory.
    // `length()` can briefly lag behind a just-written file on Windows, so the
    // authoritative check below uses the bytes actually read.
    if (await file.length() > PluginLimits.maxPackageBytes) {
      throw PluginInstallError(PluginErrorCode.packageTooLarge,
          'Package is larger than ${PluginLimits.maxPackageBytes ~/ (1024 * 1024)} MB.');
    }
    final bytes = await file.readAsBytes();
    final compressedBytes = bytes.length;
    if (compressedBytes > PluginLimits.maxPackageBytes) {
      throw PluginInstallError(PluginErrorCode.packageTooLarge,
          'Package is larger than ${PluginLimits.maxPackageBytes ~/ (1024 * 1024)} MB.');
    }
    if (compressedBytes == 0) {
      throw const PluginInstallError(
          PluginErrorCode.invalidPackage, 'The selected file is empty.');
    }

    final digest = sha256.convert(bytes).toString();

    ZipDirectory archive;
    try {
      // Read headers only. ZipDecoder(verify: true) inflates before limits.
      archive = ZipDirectory.read(InputStream(bytes));
    } catch (_) {
      throw const PluginInstallError(PluginErrorCode.invalidPackage,
          'The selected file is not a valid plugin package (zip).');
    }

    if (archive.fileHeaders.length > PluginLimits.maxEntries) {
      throw PluginInstallError(PluginErrorCode.tooManyEntries,
          'Package contains more than ${PluginLimits.maxEntries} entries.');
    }

    var declaredTotal = 0;
    for (final entry in archive.fileHeaders) {
      final mode = (entry.externalFileAttributes! >> 16) & 0xF000;
      if (mode != 0 && mode != 0x8000 && mode != 0x4000) {
        throw PluginInstallError.invalidPath(entry.filename);
      }
      final directory = entry.filename.endsWith('/');
      final name = _validatedEntryName(directory
          ? entry.filename.substring(0, entry.filename.length - 1)
          : entry.filename);
      if ((entry.file!.flags & 1) != 0 ||
          ![0, 8].contains(entry.file!.compressionMethod)) {
        throw const PluginInstallError(PluginErrorCode.invalidPackage,
            'Only unencrypted stored/deflated zip entries are supported.');
      }
      if (entry.uncompressedSize! > PluginLimits.maxFileBytes) {
        throw PluginInstallError.tooLarge(name);
      }
      declaredTotal += entry.uncompressedSize!;
      if (declaredTotal > PluginLimits.maxExtractedBytes) {
        throw PluginInstallError(PluginErrorCode.packageTooLarge,
            'Package expands beyond ${PluginLimits.maxExtractedBytes ~/ (1024 * 1024)} MB.',
            entry: name);
      }
    }
    if (declaredTotal > 0 &&
        declaredTotal / compressedBytes > PluginLimits.maxCompressionRatio) {
      throw const PluginInstallError(PluginErrorCode.suspiciousCompressionRatio,
          'Package compression ratio looks unsafe and was rejected.');
    }

    await paths.ensureCreated();
    final staging = Directory(p.join(paths.staging.path,
        '${DateTime.now().microsecondsSinceEpoch}-${_randomSuffix()}'));
    await staging.create(recursive: true);
    try {
      var reportedTotal = 0;
      final seen = <String>{};
      for (final entry in archive.fileHeaders) {
        if (entry.filename.endsWith('/')) continue;
        final name = _validatedEntryName(entry.filename);
        final key = name.toLowerCase();
        if (!seen.add(key)) {
          throw PluginInstallError(PluginErrorCode.duplicateEntry,
              'Package contains duplicate entry "$name".',
              entry: name);
        }
        final target = File(p.join(staging.path, name));
        if (!_isInside(staging.path, target.path)) {
          throw PluginInstallError.invalidPath(name);
        }
        final fileBytes = _boundedContent(entry);
        if (fileBytes.length > PluginLimits.maxFileBytes) {
          throw PluginInstallError.tooLarge(name);
        }
        reportedTotal += fileBytes.length;
        if (reportedTotal > PluginLimits.maxExtractedBytes) {
          throw PluginInstallError(PluginErrorCode.packageTooLarge,
              'Package expands beyond the limit.',
              entry: name);
        }
        await target.parent.create(recursive: true);
        await target.writeAsBytes(fileBytes, flush: true);
      }

      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        throw const PluginInstallError(
            PluginErrorCode.missingManifest, 'Package has no manifest.json.');
      }
      final manifestBytes = await manifestFile.readAsBytes();
      if (manifestBytes.length > PluginLimits.maxManifestBytes) {
        throw PluginInstallError(PluginErrorCode.manifestTooLarge,
            'manifest.json exceeds ${PluginLimits.maxManifestBytes} bytes.');
      }
      final manifestText = _decodeUtf8(manifestBytes);
      final manifest = PluginManifest.parse(manifestText,
          allowedCapabilities: allowedCapabilities);

      return PluginPackage(
        manifest: manifest,
        manifestText: manifestText,
        staging: staging,
        sha256: digest,
        compressedBytes: compressedBytes,
        warnings: List.unmodifiable(manifest.warnings),
      );
    } catch (_) {
      try {
        await staging.delete(recursive: true);
      } catch (_) {
        // Ignore; startup sweep removes stale staging directories.
      }
      rethrow;
    }
  }

  static Uint8List _boundedContent(ZipFileHeader entry) {
    final raw = entry.file!.rawContent!.toUint8List();
    final output = BytesBuilder(copy: false);
    void append(List<int> chunk) {
      if (output.length + chunk.length > PluginLimits.maxFileBytes ||
          output.length + chunk.length > entry.uncompressedSize!) {
        throw PluginInstallError.tooLarge(entry.filename);
      }
      output.add(chunk);
    }

    if (entry.file!.compressionMethod == 0) {
      append(raw);
    } else {
      final filter = RawZLibFilter.inflateFilter(raw: true);
      for (var offset = 0; offset < raw.length; offset += 1024) {
        final end = (offset + 1024).clamp(0, raw.length);
        filter.process(raw, offset, end);
        List<int>? chunk;
        while ((chunk = filter.processed(flush: false)) != null) {
          append(chunk!);
        }
      }
      List<int>? chunk;
      while ((chunk = filter.processed(end: true)) != null) {
        append(chunk!);
      }
    }
    final result = output.takeBytes();
    if (result.length != entry.uncompressedSize ||
        getCrc32(result) != entry.crc32) {
      throw const PluginInstallError(
          PluginErrorCode.invalidPackage, 'Zip size or checksum mismatch.');
    }
    return result;
  }

  static String _decodeUtf8(List<int> bytes) {
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      throw const PluginInstallError(
          PluginErrorCode.invalidManifest, 'manifest.json must be UTF-8.');
    }
  }

  static String _randomSuffix() {
    final value =
        DateTime.now().microsecondsSinceEpoch ^ identityHashCode(Object());
    return value.toRadixString(16);
  }

  static bool _isInside(String root, String candidate) {
    final normalizedRoot = p.normalize(root);
    final normalizedCandidate = p.normalize(candidate);
    return p.isWithin(normalizedRoot, normalizedCandidate);
  }

  /// Package paths are relative, forward-slash only, with no traversal or
  /// drive prefixes. Backslashes are rejected instead of rewritten so a
  /// Windows-only path can never silently become a different entry.
  static String _validatedEntryName(String rawName) {
    if (rawName.isEmpty || rawName.contains('\\')) {
      throw PluginInstallError.invalidPath(rawName);
    }
    if (rawName.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(rawName) ||
        rawName.contains(':') ||
        rawName.contains('\u0000')) {
      throw PluginInstallError.invalidPath(rawName);
    }
    final segments = rawName.split('/');
    if (segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..')) {
      throw PluginInstallError.invalidPath(rawName);
    }
    return segments.join('/');
  }
}
