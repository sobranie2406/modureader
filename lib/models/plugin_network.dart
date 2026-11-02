import 'package:anx_reader/models/plugin_manifest.dart';

/// Declarative network declarations for a P3 package.
///
/// Everything here is **data validation only**: P3a parses and rejects, it never
/// opens a socket. The request/response objects are shape-checked so that by the
/// time P3b's transport runs, every value it touches is already known-good.
///
/// See docs/development/plugin-p3-security-review.md for the threat model.

/// A host name a package may contact. Never an address: the guard validates the
/// *name* against the allowlist and separately validates every resolved address.
class PluginAllowlist {
  const PluginAllowlist._();

  static const int maxDomains = 8;
  static const int maxHostLength = 253;

  /// Names that must never appear in an allowlist regardless of resolution.
  static const Set<String> blockedSuffixes = {
    '.local',
    '.internal',
    '.home.arpa',
    '.localhost',
  };

  static const Set<String> blockedNames = {'localhost'};

  /// True when [value] parses as an IPv4/IPv6 literal in any common notation.
  ///
  /// The allowlist is a name allowlist, so a literal is always rejected rather
  /// than normalised: `127.0.0.1`, `0x7f.1`, `2130706433` and `[::1]` all fail.
  static bool isIpLiteral(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;
    if (text.startsWith('[') && text.endsWith(']')) return true;
    if (text.contains(':')) return true; // IPv6 without brackets
    // A single label that is decimal, octal or hex is a numeric IPv4 literal
    // (e.g. 2130706433, 0x7f000001, 017700000001), not a host name.
    if (!text.contains('.') &&
        RegExp(r'^(0[xX][0-9a-fA-F]+|[0-9]+)$').hasMatch(text)) {
      return true;
    }
    final parts = text.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      if (part.isEmpty) return true;
      final octal = part.length > 1 && part.startsWith('0');
      final hex = part.toLowerCase().startsWith('0x');
      final valid = hex
          ? RegExp(r'^0x[0-9a-f]{1,2}$').hasMatch(part.toLowerCase())
          : octal
              ? RegExp(r'^0[0-7]{1,3}$').hasMatch(part)
              : RegExp(r'^[0-9]{1,3}$').hasMatch(part);
      if (!valid) return false;
      final number = hex
          ? int.parse(part.substring(2), radix: 16)
          : octal
              ? int.parse(part.substring(1), radix: 8)
              : int.parse(part);
      if (number > 255) return false;
    }
    return true;
  }

  /// Validates one allowlist entry and returns its normalised form.
  static String validate(String raw, String field) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, '$field must not be empty.');
    }
    if (value.length > maxHostLength) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          '$field exceeds $maxHostLength characters.');
    }
    if (value != raw) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          '$field must not contain leading or trailing whitespace.');
    }
    if (value != value.toLowerCase()) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, '$field must be lowercase.');
    }
    if (value.endsWith('.')) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          '$field must not end with a dot.');
    }
    for (final forbidden in ['@', '%', '\\', ' ', '*', '/', '?', '#']) {
      if (value.contains(forbidden)) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            '$field must be a plain host name.');
      }
    }
    if (value.runes.any((rune) => rune < 0x21 || rune == 0x7f)) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          '$field must not contain control characters.');
    }
    if (isIpLiteral(value)) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          '$field must be a host name, not an IP address.');
    }
    if (blockedNames.contains(value)) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          '$field must not be a local host name.');
    }
    for (final suffix in blockedSuffixes) {
      if (value == suffix.substring(1) || value.endsWith(suffix)) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            '$field must not be a local host name.');
      }
    }
    if (!RegExp(r'^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$').hasMatch(value) ||
        value.contains('..')) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, '$field is not a valid host name.');
    }
    return value;
  }
}

/// The `network` block of a `net:http` manifest.
class PluginNetwork {
  const PluginNetwork({
    required this.domains,
    required this.timeoutMs,
    required this.maxResponseBytes,
    required this.requestsPerLookup,
  });

  final List<String> domains;
  final int timeoutMs;
  final int maxResponseBytes;
  final int requestsPerLookup;

  static const int minTimeoutMs = 1000;
  static const int maxTimeoutMs = 15000;
  static const int defaultTimeoutMs = 8000;
  static const int minResponseBytes = 4096;
  static const int maxResponseBytesLimit = 1024 * 1024;

  /// P3 v1 issues exactly one request per lookup; anything else is rejected so a
  /// manifest cannot turn one user action into a fan-out.
  static const int requestsPerLookupFixed = 1;

  static PluginNetwork parse(Object? raw) {
    if (raw is! Map) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'network must be an object when the package declares net:http.');
    }
    final rawDomains = raw['domains'];
    if (rawDomains is! List || rawDomains.isEmpty) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'network.domains must be a non-empty array.');
    }
    if (rawDomains.length > PluginAllowlist.maxDomains) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'network.domains may list at most ${PluginAllowlist.maxDomains} hosts.');
    }
    final domains = <String>[];
    for (final entry in rawDomains) {
      if (entry is! String) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            'network.domains must contain host names.');
      }
      final domain = PluginAllowlist.validate(entry, 'network.domains');
      if (domains.contains(domain)) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            'network.domains contains a duplicate host.');
      }
      domains.add(domain);
    }

    final timeout = raw['timeoutMs'] ?? defaultTimeoutMs;
    if (timeout is! int || timeout < minTimeoutMs || timeout > maxTimeoutMs) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest,
          'network.timeoutMs must be between $minTimeoutMs and $maxTimeoutMs.');
    }

    final maxBytes = raw['maxResponseBytes'] ?? maxResponseBytesLimit;
    if (maxBytes is! int ||
        maxBytes < minResponseBytes ||
        maxBytes > maxResponseBytesLimit) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest,
          'network.maxResponseBytes must be between $minResponseBytes and '
          '$maxResponseBytesLimit.');
    }

    final perLookup = raw['requestsPerLookup'] ?? requestsPerLookupFixed;
    if (perLookup != requestsPerLookupFixed) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'network.requestsPerLookup must be $requestsPerLookupFixed.');
    }

    return PluginNetwork(
      domains: List<String>.unmodifiable(domains),
      timeoutMs: timeout,
      maxResponseBytes: maxBytes,
      requestsPerLookup: perLookup,
    );
  }

  bool allows(String host) => domains.contains(host);
}

/// A declarative GET request. The host builds it; the manifest only supplies
/// templates, and every template is validated here rather than at request time.
class PluginRequestTemplate {
  const PluginRequestTemplate({
    required this.method,
    required this.url,
    required this.query,
    required this.headers,
  });

  final String method;

  /// Path template, always beginning with `/`. Never carries a query or host.
  final String url;

  /// Ordered query parameters; keys are literal, values are templates.
  final Map<String, String> query;

  /// Header name → template. Only three names are allowed, and `Authorization`
  /// may contain nothing but a secret reference.
  final Map<String, String> headers;

  static const int maxTemplates = 16;
  static const int maxTemplateLength = 1024;
  static const int maxQueryValueLength = 256;

  static const Set<String> allowedHeaders = {
    'Accept',
    'Accept-Language',
    'Authorization',
  };

  static const String wordPlaceholder = '{word}';

  /// `{setting.<key>}`; deliberately excludes secrets.
  static final RegExp settingPlaceholder =
      RegExp(r'\{setting\.([a-z][a-z0-9_]{0,39})\}');

  /// `{secret.<key>}`; allowed only in `Authorization`.
  static final RegExp secretPlaceholder =
      RegExp(r'\{secret\.([a-z][a-z0-9_]{0,39})\}');

  /// Any other `{...}` is rejected so a typo cannot silently leak or vanish.
  static final RegExp anyPlaceholder = RegExp(r'\{[^}]*\}');

  static PluginRequestTemplate parse(Object? raw, PluginNetwork network) {
    if (raw is! Map) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, 'request must be an object.');
    }
    final method = (raw['method'] ?? '').toString().toUpperCase();
    if (method != 'GET') {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'request.method must be GET; other methods are not supported.');
    }
    final url = raw['url'];
    if (url is! String || !url.startsWith('/')) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'request.url must be an absolute path beginning with "/".');
    }
    if (url.length > maxTemplateLength) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'request.url exceeds $maxTemplateLength characters.');
    }
    if (url.contains('?') || url.contains('#')) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'request.url must not contain a query or fragment; declare request.query instead.');
    }
    if (url.contains('://') || url.startsWith('//')) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'request.url must be a path, not a URL; the host comes from network.domains.');
    }
    _validatePlaceholders(url, 'request.url', allowSecret: false, allowWord: true);

    final rawQuery = raw['query'] ?? const <String, dynamic>{};
    if (rawQuery is! Map) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, 'request.query must be an object.');
    }
    if (rawQuery.length > maxTemplates) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'request.query may declare at most $maxTemplates parameters.');
    }
    final query = <String, String>{};
    for (final entry in rawQuery.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.isEmpty || key.length > 128) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            'request.query keys must be 1-128 characters.');
      }
      if (anyPlaceholder.hasMatch(key)) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            'request.query keys must be literal; placeholders belong in values.');
      }
      if (value is! String || value.isEmpty || value.length > maxQueryValueLength) {
        throw PluginInstallError(
            PluginErrorCode.invalidManifest,
            'request.query values must be strings of 1-$maxQueryValueLength characters.');
      }
      _validatePlaceholders(value, 'request.query', allowSecret: false, allowWord: true);
      query[key] = value;
    }

    final rawHeaders = raw['headers'] ?? const <String, dynamic>{};
    if (rawHeaders is! Map) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, 'request.headers must be an object.');
    }
    final headers = <String, String>{};
    for (final entry in rawHeaders.entries) {
      final name = entry.key;
      final value = entry.value;
      if (name is! String || !allowedHeaders.contains(name)) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            'request.headers may only set Accept, Accept-Language and Authorization; '
            'host-controlled headers cannot be overridden.');
      }
      if (headers.containsKey(name)) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            'request.headers contains a duplicate name.');
      }
      if (value is! String ||
          value.isEmpty ||
          value.length > maxTemplateLength ||
          value.contains('\r') ||
          value.contains('\n')) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            'request.headers values must be single-line strings.');
      }
      if (name == 'Authorization') {
        // Nothing but the secret may appear, so a manifest cannot build
        // "Bearer <secret><attacker text>" or smuggle a second header.
        final secret = value.replaceFirst(RegExp(r'^Bearer '), '');
        if (!secretPlaceholder.hasMatch(secret) ||
            secret.replaceAll(secretPlaceholder, '').isNotEmpty) {
          throw PluginInstallError(PluginErrorCode.invalidManifest,
              'Authorization may contain only a single {secret.<key>} reference.');
        }
      } else if (secretPlaceholder.hasMatch(value)) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            'Secrets may only be used in the Authorization header.');
      }
      _validatePlaceholders(value, 'request.headers', allowSecret: name == 'Authorization',
          allowWord: false);
      headers[name] = value;
    }

    return PluginRequestTemplate(
      method: method,
      url: url,
      query: Map<String, String>.unmodifiable(query),
      headers: Map<String, String>.unmodifiable(headers),
    );
  }

  /// Rejects any `{...}` that is not an explicitly permitted placeholder.
  static void _validatePlaceholders(
    String value,
    String field, {
    required bool allowSecret,
    required bool allowWord,
  }) {
    for (final match in anyPlaceholder.allMatches(value)) {
      final token = match.group(0)!;
      if (allowWord && token == wordPlaceholder) continue;
      if (settingPlaceholder.hasMatch(token) && token.length == match.group(0)!.length) {
        // A full `{setting.<key>}` token is fine.
        if (token.replaceAll(settingPlaceholder, '').isEmpty) continue;
      }
      if (allowSecret && secretPlaceholder.hasMatch(token)) {
        if (token.replaceAll(secretPlaceholder, '').isEmpty) continue;
      }
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          '$field uses an unsupported placeholder: $token');
    }
    if (value.length > maxTemplateLength) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          '$field exceeds $maxTemplateLength characters.');
    }
  }
}

/// One step of a JSON path: an object key, an array index or an array wildcard.
sealed class JsonPathSegment {
  const JsonPathSegment();
}

class JsonPathKey extends JsonPathSegment {
  const JsonPathKey(this.name);
  final String name;
}

class JsonPathIndex extends JsonPathSegment {
  const JsonPathIndex(this.index);
  final int index;
}

class JsonPathWildcard extends JsonPathSegment {
  const JsonPathWildcard();
}

/// A parsed JSON path such as `data.entries[*].senses[*].definition`.
///
/// P3a parses and validates only; evaluation lands with the transport in P3b. The
/// grammar is deliberately tiny: object keys, array indexes and a wildcard, with
/// no filters, functions, recursion or expressions.
class JsonPath {
  const JsonPath(this.segments);

  final List<JsonPathSegment> segments;

  static const int maxSegments = 32;

  static final RegExp _keyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]{0,63}$');

  static JsonPath parse(String raw, String field) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, '$field must not be empty.');
    }
    if (text.length > 512) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          '$field exceeds 512 characters.');
    }
    final segments = <JsonPathSegment>[];
    var index = 0;
    var expectSegment = true;
    while (index < text.length) {
      final char = text[index];
      if (char == '.') {
        if (expectSegment) {
          throw PluginInstallError(PluginErrorCode.invalidManifest,
              '$field has an empty segment.');
        }
        expectSegment = true;
        index++;
        continue;
      }
      if (char == '[') {
        final end = text.indexOf(']', index);
        if (end < 0) {
          throw PluginInstallError(
              PluginErrorCode.invalidManifest, '$field has an unclosed "[".');
        }
        final inner = text.substring(index + 1, end);
        if (inner == '*') {
          segments.add(const JsonPathWildcard());
        } else if (RegExp(r'^[0-9]{1,3}$').hasMatch(inner)) {
          segments.add(JsonPathIndex(int.parse(inner)));
        } else {
          throw PluginInstallError(PluginErrorCode.invalidManifest,
              '$field supports only [n] and [*], not "[$inner]".');
        }
        index = end + 1;
        expectSegment = false;
        continue;
      }
      final start = index;
      while (index < text.length && text[index] != '.' && text[index] != '[') {
        index++;
      }
      final name = text.substring(start, index);
      if (!_keyPattern.hasMatch(name)) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            '$field has an invalid key "$name".');
      }
      segments.add(JsonPathKey(name));
      expectSegment = false;
    }
    if (segments.isEmpty || expectSegment) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, '$field is not a valid JSON path.');
    }
    if (segments.length > maxSegments) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          '$field may contain at most $maxSegments segments.');
    }
    return JsonPath(List<JsonPathSegment>.unmodifiable(segments));
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    for (final segment in segments) {
      switch (segment) {
        case JsonPathKey(:final name):
          if (buffer.isNotEmpty) buffer.write('.');
          buffer.write(name);
        case JsonPathIndex(:final index):
          buffer.write('[$index]');
        case JsonPathWildcard():
          buffer.write('[*]');
      }
    }
    return buffer.toString();
  }
}

/// Declarative mapping from a JSON response to dictionary entries.
class PluginResponseMapping {
  const PluginResponseMapping({
    required this.format,
    required this.root,
    required this.fields,
    required this.maxEntries,
    required this.maxDefinitionChars,
  });

  final String format;

  /// Path to the array/object the field paths are relative to; null means the
  /// document root.
  final JsonPath? root;

  /// Field name → path relative to [root].
  final Map<String, JsonPath> fields;

  final int maxEntries;
  final int maxDefinitionChars;

  /// `definition` is mandatory; the rest are optional metadata.
  static const Set<String> allowedFields = {
    'definition',
    'word',
    'partOfSpeech',
    'sourceUrl',
    'license',
    'attribution',
    'licenseUri',
  };

  static const int defaultMaxEntries = 5;
  static const int maxEntriesLimit = 20;
  static const int defaultMaxDefinitionChars = 4000;
  static const int minDefinitionChars = 100;
  static const int maxDefinitionCharsLimit = 20000;

  static PluginResponseMapping parse(Object? raw) {
    if (raw is! Map) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, 'response must be an object.');
    }
    final format = raw['format'] ?? 'json';
    if (format != 'json') {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'response.format must be "json"; HTML parsing is not supported.');
    }
    final rawRoot = raw['root'];
    final root = rawRoot == null
        ? null
        : JsonPath.parse(rawRoot.toString(), 'response.root');

    final rawFields = raw['fields'];
    if (rawFields is! Map || rawFields.isEmpty) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'response.fields must be a non-empty object.');
    }
    final fields = <String, JsonPath>{};
    for (final entry in rawFields.entries) {
      final name = entry.key;
      if (name is! String || !allowedFields.contains(name)) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            'response.fields may only map ${allowedFields.join(', ')}.');
      }
      if (entry.value is! String) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            'response.fields values must be JSON path strings.');
      }
      fields[name] =
          JsonPath.parse(entry.value as String, 'response.fields.$name');
    }
    if (!fields.containsKey('definition')) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'response.fields must map "definition".');
    }

    final maxEntries = raw['maxEntries'] ?? defaultMaxEntries;
    if (maxEntries is! int || maxEntries < 1 || maxEntries > maxEntriesLimit) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'response.maxEntries must be between 1 and $maxEntriesLimit.');
    }

    final maxChars =
        raw['maxDefinitionChars'] ?? defaultMaxDefinitionChars;
    if (maxChars is! int ||
        maxChars < minDefinitionChars ||
        maxChars > maxDefinitionCharsLimit) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest,
          'response.maxDefinitionChars must be between $minDefinitionChars and '
          '$maxDefinitionCharsLimit.');
    }

    return PluginResponseMapping(
      format: format,
      root: root,
      fields: Map<String, JsonPath>.unmodifiable(fields),
      maxEntries: maxEntries,
      maxDefinitionChars: maxChars,
    );
  }
}