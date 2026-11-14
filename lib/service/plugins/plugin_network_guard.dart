import 'dart:io';

import 'package:modu_reader/models/plugin_network.dart';
import 'package:modu_reader/service/dictionary/local_dictionary.dart';

/// Result of validating a plugin request before anything is sent.
class PluginGuardResult {
  const PluginGuardResult({
    required this.uri,
    required this.addresses,
    required this.headers,
  });

  final Uri uri;

  /// The exact addresses that were validated. The request must connect to one of
  /// these, never to a fresh resolution of [uri].host — re-resolving at connect
  /// time reopens the DNS-rebinding window this guard exists to close.
  final List<InternetAddress> addresses;

  final Map<String, String> headers;
}

/// Validates plugin network requests. Never performs I/O beyond DNS resolution,
/// and never reads a response.
///
/// See docs/development/plugin-p3-security-review.md §3 T1 for the rationale
/// behind each check.
class PluginNetworkGuard {
  PluginNetworkGuard({
    Future<List<InternetAddress>> Function(String host)? resolver,
  }) : _resolver = resolver ?? _defaultResolver;

  final Future<List<InternetAddress>> Function(String host) _resolver;

  static Future<List<InternetAddress>> _defaultResolver(String host) =>
      InternetAddress.lookup(host);

  /// Validates [uri] against [network] and resolves it.
  ///
  /// Throws [DictionaryFailure] with a code the UI can show; the message never
  /// contains the host, the word or any header value.
  Future<PluginGuardResult> validate({
    required PluginNetwork network,
    required Uri uri,
    required Map<String, String> headers,
  }) async {
    _validateShape(uri, network);
    final addresses = await _resolve(uri.host);
    return PluginGuardResult(uri: uri, addresses: addresses, headers: headers);
  }

  void _validateShape(Uri uri, PluginNetwork network) {
    if (uri.scheme != 'https') {
      throw const DictionaryFailure('configuration');
    }
    if (uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw const DictionaryFailure('configuration');
    }
    if (uri.hasPort && uri.port != 443) {
      throw const DictionaryFailure('configuration');
    }
    if (uri.host.isEmpty) {
      throw const DictionaryFailure('configuration');
    }
    // The host must already be normalised by PluginAllowlist; a dot or an
    // uppercase letter here means the caller bypassed manifest validation.
    final host = uri.host;
    if (host != host.toLowerCase() || host.endsWith('.')) {
      throw const DictionaryFailure('configuration');
    }
    if (PluginAllowlist.isIpLiteral(host)) {
      throw const DictionaryFailure('configuration');
    }
    if (!network.allows(host)) {
      throw const DictionaryFailure('configuration');
    }
  }

  Future<List<InternetAddress>> _resolve(String host) async {
    final List<InternetAddress> addresses;
    try {
      addresses = await _resolver(host);
    } catch (_) {
      throw const DictionaryFailure('network');
    }
    if (addresses.isEmpty) {
      throw const DictionaryFailure('network');
    }
    // Every record must be public: a single private answer fails the request,
    // because the resolver response is attacker-influenced.
    for (final address in addresses) {
      if (!isPublicAddress(address)) {
        throw const DictionaryFailure('configuration');
      }
    }
    return addresses;
  }

  /// True when [address] is routable public unicast.
  ///
  /// Deliberately allowlist-shaped: anything unrecognised counts as unsafe, so a
  /// newly added Dart platform cannot widen the accepted range by accident.
  static bool isPublicAddress(InternetAddress address) {
    if (address.type == InternetAddressType.unix) return false;
    final bytes = address.rawAddress;
    if (bytes.length == 4) return _isPublicV4(bytes);
    if (bytes.length == 16) return _isPublicV6(bytes);
    return false;
  }

  static bool _isPublicV4(List<int> bytes) {
    final a = bytes[0], b = bytes[1];
    if (a == 0) return false; // 0.0.0.0/8 "this network"
    if (a == 10) return false; // private
    if (a == 127) return false; // loopback
    if (a == 169 && b == 254) return false; // link-local (cloud metadata)
    if (a == 172 && b >= 16 && b <= 31) return false; // private
    if (a == 192 && b == 168) return false; // private
    if (a == 192 && b == 0) return false; // IETF protocol assignments
    if (a == 100 && b >= 64 && b <= 127) return false; // CGNAT
    if (a == 198 && (b == 18 || b == 19)) return false; // benchmarking
    if (a >= 224) return false; // multicast, reserved, broadcast
    return true;
  }

  static bool _isPublicV6(List<int> bytes) {
    // IPv4-mapped ::ffff:a.b.c.d — re-check the embedded address, so
    // ::ffff:127.0.0.1 is rejected.
    final isMapped = bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    if (isMapped) return _isPublicV4(bytes.sublist(12));
    // Only native global unicast (2000::/3), never local/translation space.
    if ((bytes[0] & 0xe0) != 0x20) return false;
    if (bytes[0] == 0x20 && bytes[1] == 0x02) return false; // 6to4
    if (bytes[0] == 0x20 &&
        bytes[1] == 0x01 &&
        bytes[2] == 0 &&
        bytes[3] == 0) {
      return false; // Teredo can embed an otherwise forbidden IPv4 target.
    }
    if (bytes[0] == 0x20 &&
        bytes[1] == 0x01 &&
        bytes[2] == 0x0d &&
        bytes[3] == 0xb8) {
      return false;
    }
    // Documentation allocations: 2001:db8::/32 above and 3fff::/20.
    if (bytes[0] == 0x3f && bytes[1] == 0xff && (bytes[2] & 0xf0) == 0) {
      return false;
    }
    return true;
  }
}
