import 'dart:convert';
import 'dart:io';

const _moduPrefix = 'modu:';
const _readAnyPrefix = 'readany:';
const _maxEncodedLength = 512 * 1024;
const _maxDecodedLength = 2 * 1024 * 1024;

enum ConfigTransferSource { modu, readAny }

class DecodedConfigTransfer {
  const DecodedConfigTransfer({
    required this.source,
    required this.data,
    this.kind,
    this.version,
  });

  final ConfigTransferSource source;
  final String? kind;
  final int? version;
  final Map<String, dynamic> data;
}

/// Encodes configuration as a short, copyable token inspired by ReadAny's
/// `readany:<base64-json>` transfer code.
///
/// Modu uses gzip before Base64 so configurations with multiple providers and
/// API keys remain small enough for a QR code. Base64 is transport encoding,
/// not encryption; callers must present a secret-data warning to the user.
class ConfigTransferCodec {
  const ConfigTransferCodec._();

  static String encode({
    required String kind,
    required Map<String, dynamic> data,
  }) {
    if (kind.trim().isEmpty) {
      throw const FormatException('配置类型不能为空');
    }
    final envelope = <String, dynamic>{
      'version': 1,
      'kind': kind.trim(),
      'data': data,
    };
    final bytes = utf8.encode(jsonEncode(envelope));
    return '$_moduPrefix${base64Encode(gzip.encode(bytes))}';
  }

  static DecodedConfigTransfer decode(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty || trimmed.length > _maxEncodedLength) {
      throw const FormatException('配置代码为空或过长');
    }

    if (trimmed.startsWith(_moduPrefix)) {
      final decoded = _decodePayload(trimmed.substring(_moduPrefix.length));
      final version = decoded['version'];
      final kind = decoded['kind'];
      final data = decoded['data'];
      if (version is! int || version != 1 || kind is! String || data is! Map) {
        throw const FormatException('默读配置代码格式无效');
      }
      return DecodedConfigTransfer(
        source: ConfigTransferSource.modu,
        version: version,
        kind: kind,
        data: Map<String, dynamic>.from(data),
      );
    }

    if (trimmed.startsWith(_readAnyPrefix)) {
      final decoded = _decodePayload(
        trimmed.substring(_readAnyPrefix.length),
        allowGzip: false,
      );
      return DecodedConfigTransfer(
        source: ConfigTransferSource.readAny,
        data: decoded,
      );
    }

    throw const FormatException('无法识别配置代码前缀');
  }

  static Map<String, dynamic> _decodePayload(
    String encoded, {
    bool allowGzip = true,
  }) {
    try {
      final bytes = base64Decode(encoded.replaceAll(RegExp(r'\s+'), ''));
      final payload =
          allowGzip && _looksLikeGzip(bytes) ? gzip.decode(bytes) : bytes;
      if (payload.length > _maxDecodedLength) {
        throw const FormatException('配置内容过大');
      }
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map) {
        throw const FormatException('配置内容必须是对象');
      }
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('配置代码损坏或不完整');
    }
  }

  static bool _looksLikeGzip(List<int> bytes) {
    return bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
  }
}
