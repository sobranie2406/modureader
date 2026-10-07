import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 's3_config.dart';

/// RFC 3986 / AWS encoding (not form encoding). Preserve key case and slashes.
String s3Encode(String value) => Uri.encodeComponent(value).replaceAllMapped(
    RegExp("[!'()*]"),
    (m) => '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}');

Uri s3Uri(S3Config config, String? key, Map<String, String> query) {
  final segments = [
    if (config.addressing == 'path') config.bucket,
    if (key != null) ...key.split('/')
  ];
  final host = config.addressing == 'virtual'
      ? '${config.bucket}.${config.endpoint.host}'
      : config.endpoint.host;
  final port = config.endpoint.hasPort ? ':${config.endpoint.port}' : '';
  final keys = query.keys.toList()..sort();
  final qs = keys.map((k) => '${s3Encode(k)}=${s3Encode(query[k]!)}').join('&');
  return Uri.parse('${config.endpoint.scheme}://$host$port/'
      '${segments.map(s3Encode).join('/')}${qs.isEmpty ? '' : '?$qs'}');
}

Map<String, String> signS3Request(
    {required S3Config config,
    required String method,
    required Uri uri,
    required String? key,
    required String payloadHash,
    required DateTime now,
    Map<String, String> headers = const {}}) {
  final result = <String, String>{...headers};
  if (config.signature == 'v2') {
    result.putIfAbsent('date', () => HttpDate.format(now.toUtc()));
    if (config.token.isNotEmpty) result['x-amz-security-token'] = config.token;
    final amz = result.keys.where((k) => k.startsWith('x-amz-')).toList()
      ..sort();
    final canonicalAmz = amz.map((k) => '$k:${result[k]!.trim()}\n').join();
    // ListObjects query parameters are not S3 v2 signed subresources.
    final resource =
        '/${config.bucket}/${key == null ? '' : key.split('/').map(s3Encode).join('/')}';
    final toSign = '$method\n${result['content-md5'] ?? ''}\n'
        '${result['content-type'] ?? ''}\n${result['date']}\n$canonicalAmz$resource';
    final sig = base64Encode(Hmac(sha1, utf8.encode(config.secretKey))
        .convert(utf8.encode(toSign))
        .bytes);
    result['authorization'] = 'AWS ${config.accessKey}:$sig';
    return result;
  }
  final timestamp = now
          .toUtc()
          .toIso8601String()
          .replaceAll(RegExp('[:-]'), '')
          .substring(0, 15) +
      'Z';
  final day = timestamp.substring(0, 8);
  result['host'] = uri.authority;
  result['x-amz-date'] = timestamp;
  result['x-amz-content-sha256'] = payloadHash;
  if (config.token.isNotEmpty) result['x-amz-security-token'] = config.token;
  final names = result.keys.toList()..sort();
  final canonicalHeaders = names
      .map((k) => '$k:${result[k]!.trim().replaceAll(RegExp(r'\s+'), ' ')}\n')
      .join();
  final signedHeaders = names.join(';');
  final canonical =
      '$method\n${uri.path}\n${uri.query}\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
  final scope = '$day/${config.region}/s3/aws4_request';
  final toSign =
      'AWS4-HMAC-SHA256\n$timestamp\n$scope\n${sha256.convert(utf8.encode(canonical))}';
  List<int> hmac(List<int> key, String value) =>
      Hmac(sha256, key).convert(utf8.encode(value)).bytes;
  var signingKey = hmac(utf8.encode('AWS4${config.secretKey}'), day);
  for (final part in [config.region, 's3', 'aws4_request']) {
    signingKey = hmac(signingKey, part);
  }
  final sig = Hmac(sha256, signingKey).convert(utf8.encode(toSign));
  result['authorization'] =
      'AWS4-HMAC-SHA256 Credential=${config.accessKey}/$scope, SignedHeaders=$signedHeaders, Signature=$sig';
  return result;
}
