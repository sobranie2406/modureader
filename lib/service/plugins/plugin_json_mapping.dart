import 'package:anx_reader/models/plugin_network.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';

/// Evaluates a [JsonPath] against decoded JSON and maps the result into
/// dictionary entries.
///
/// This is **data traversal only**. There is no expression language, no filter,
/// no function call and no recursive descent: the path was already reduced to a
/// list of segments by [JsonPath.parse], so nothing here can execute user input.
///
/// Limits are enforced *before* values are joined, so a hostile document cannot
/// exhaust memory through a wide wildcard.
class PluginJsonMapping {
  const PluginJsonMapping._();

  /// Structural ceilings from the security review (§3 T4).
  static const int maxDepth = 32;
  static const int maxNodes = 100000;
  static const int maxTotalStringLength = 2 * 1024 * 1024;

  /// Checks the decoded document against the structural limits.
  ///
  /// Iterative rather than recursive so a deeply nested document cannot overflow
  /// the stack before the depth check fires.
  static void checkStructure(Object? document) {
    var nodes = 0;
    var stringLength = 0;
    final stack = <(Object?, int)>[(document, 0)];
    while (stack.isNotEmpty) {
      final (value, depth) = stack.removeLast();
      if (++nodes > maxNodes) {
        throw const DictionaryFailure('invalidResponse');
      }
      if (depth > maxDepth) {
        throw const DictionaryFailure('invalidResponse');
      }
      if (value is String) {
        stringLength += value.length;
        if (stringLength > maxTotalStringLength) {
          throw const DictionaryFailure('invalidResponse');
        }
      } else if (value is Map) {
        for (final entry in value.entries) {
          stack.add((entry.key, depth + 1));
          stack.add((entry.value, depth + 1));
        }
      } else if (value is List) {
        for (final element in value) {
          stack.add((element, depth + 1));
        }
      }
    }
  }

  /// Resolves [path] against [document], returning every matched value.
  static List<Object?> evaluate(JsonPath path, Object? document) {
    var current = <Object?>[document];
    for (final segment in path.segments) {
      final next = <Object?>[];
      for (final node in current) {
        switch (segment) {
          case JsonPathKey(:final name):
            // A key only reads an object; missing keys yield nothing.
            if (node is Map && node.containsKey(name)) {
              next.add(node[name]);
            }
          case JsonPathIndex(:final index):
            if (node is List && index < node.length) {
              next.add(node[index]);
            }
          case JsonPathWildcard():
            if (node is List) next.addAll(node);
        }
        if (next.length > maxNodes) {
          throw const DictionaryFailure('invalidResponse');
        }
      }
      current = next;
      if (current.isEmpty) return const [];
    }
    return current;
  }

  /// Reads a single scalar field, returning null when absent or not printable.
  static String? readScalar(JsonPath path, Object? document) {
    final values = evaluate(path, document);
    final text = values.map(_stringify).whereType<String>().join('\n').trim();
    return text.isEmpty ? null : text;
  }

  /// Expands nested lists into scalars so one array is many definitions.
  static List<String> _flatten(Object? value) {
    if (value is List) {
      return value.expand(_flatten).toList(growable: false);
    }
    final single = _stringify(value);
    return single == null ? const [] : [single];
  }

  static String? _stringify(Object? value) {
    if (value == null) return null;
    if (value is String) return _clean(value);
    if (value is num || value is bool) return value.toString();
    if (value is List) {
      return value
          .map(_stringify)
          .whereType<String>()
          .where((text) => text.isNotEmpty)
          .join('\n');
    }
    return null;
  }

  /// Strips control characters other than newline and tab.
  static String _clean(String value) =>
      value.replaceAll(RegExp(r'[\x00-\x08\x0B-\x1F\x7F]'), '');

  /// Maps a response into at most [PluginResponseMapping.maxEntries] entries.
  ///
  /// A document that yields no definition returns an empty list: "no entry
  /// found" is a normal outcome, not a failure.
  static List<DictionaryEntry> map({
    required Object? document,
    required PluginResponseMapping mapping,
    required String sourceId,
    required String sourceLabel,
    required String license,
    required String attribution,
    required String? licenseUri,
    required String? sourceUrl,
    required String word,
  }) {
    checkStructure(document);
    final root = mapping.root == null
        ? document
        : _single(evaluate(mapping.root!, document));

    // Each matched value is one definition. A value that is itself a list is
    // expanded, so `[*]` over an array of strings yields one entry each rather
    // than a single entry containing the whole array.
    final definitions = <String>[];
    for (final value in evaluate(mapping.fields['definition']!, root)) {
      for (final text in _flatten(value)) {
        final trimmed = text.trim();
        if (trimmed.isNotEmpty) definitions.add(trimmed);
      }
    }
    if (definitions.isEmpty) return const [];

    final entryWord = mapping.fields['word'] == null
        ? word
        : readScalar(mapping.fields['word']!, root) ?? word;
    final partOfSpeech = mapping.fields['partOfSpeech'] == null
        ? null
        : readScalar(mapping.fields['partOfSpeech']!, root);
    final remoteLicense = mapping.fields['license'] == null
        ? null
        : readScalar(mapping.fields['license']!, root);
    final remoteAttribution = mapping.fields['attribution'] == null
        ? null
        : readScalar(mapping.fields['attribution']!, root);
    final remoteSourceUrl = _httpsOrNull(
        mapping.fields['sourceUrl'] == null
            ? null
            : readScalar(mapping.fields['sourceUrl']!, root));
    final remoteLicenseUri = _httpsOrNull(
        mapping.fields['licenseUri'] == null
            ? null
            : readScalar(mapping.fields['licenseUri']!, root));

    // A flat definition list is still one entry per definition, matching how
    // the built-in sources present multiple senses.
    final limited = definitions.take(mapping.maxEntries);
    final entries = <DictionaryEntry>[];
    for (final definition in limited) {
      final text = definition.length > mapping.maxDefinitionChars
          ? '${definition.substring(0, mapping.maxDefinitionChars)}…'
          : definition;
      entries.add(DictionaryEntry(
        sourceLabel,
        entryWord,
        partOfSpeech == null || partOfSpeech.isEmpty
            ? text
            : '$partOfSpeech. $text',
        dictionaryId: sourceId,
        sourceUri: remoteSourceUrl == null ? null : Uri.tryParse(remoteSourceUrl) ??
            (sourceUrl == null ? null : Uri.tryParse(sourceUrl)),
        license: remoteLicense ?? license,
        licenseUri: remoteLicenseUri == null
            ? (licenseUri == null ? null : Uri.tryParse(licenseUri))
            : Uri.tryParse(remoteLicenseUri),
        attribution: remoteAttribution ?? attribution,
      ));
    }
    return entries;
  }

  static Object? _single(List<Object?> values) =>
      values.isEmpty ? null : values.first;

  /// Metadata URLs must be https; a bad one is dropped rather than failing the
  /// whole lookup, because it is provenance, not content.
  static String? _httpsOrNull(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri.toString();
  }
}
