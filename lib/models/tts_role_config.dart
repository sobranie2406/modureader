import 'package:flutter/foundation.dart';

/// Speaker of a synthesized run. Only [narration] and [dialogue] are produced by
/// the automatic splitter; [character] is reserved for explicit book-level
/// assignments added by later releases.
enum TtsSpeakerRole { narration, dialogue, character }

/// Longest run handed to one synthesis request. Kept in line with the online
/// buffer default so a split paragraph cannot exceed the provider limit.
const int ttsRoleMaxRunCharacters = 240;

/// A named speaker the reader can map to its own voice.
///
/// Stored but not yet surfaced: keeping the field in the persisted shape now
/// means later releases can add character voices without a settings migration.
@immutable
class TtsCharacterRole {
  const TtsCharacterRole({
    required this.id,
    required this.name,
    required this.voice,
  });

  final String id;
  final String name;

  /// Provider voice short name; empty means "follow the dialogue voice".
  final String voice;

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'voice': voice};

  static TtsCharacterRole? fromMap(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    final voice = value['voice'];
    return TtsCharacterRole(
      id: id,
      name: name,
      voice: voice is String ? voice : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsCharacterRole &&
          other.id == id &&
          other.name == name &&
          other.voice == voice;

  @override
  int get hashCode => Object.hash(id, name, voice);
}

/// Narration/dialogue voices. Empty voices mean "inherit the existing single
/// voice", so an untouched configuration never changes playback.
@immutable
class TtsRoleConfig {
  const TtsRoleConfig({
    this.enabled = false,
    this.narrationVoice = '',
    this.dialogueVoice = '',
    this.characters = const [],
  });

  static const TtsRoleConfig disabled = TtsRoleConfig();

  final bool enabled;
  final String narrationVoice;
  final String dialogueVoice;
  final List<TtsCharacterRole> characters;

  /// True when the reader actually has to split text into different voices.
  bool get isDistinct {
    if (!enabled) return false;
    final narration = narrationVoice.trim();
    final dialogue = dialogueVoice.trim();
    if (narration.isEmpty && dialogue.isEmpty) return false;
    return narration != dialogue;
  }

  String narrationVoiceFor(String fallback) {
    final value = narrationVoice.trim();
    return value.isEmpty ? fallback : value;
  }

  String dialogueVoiceFor(String fallback) {
    final value = dialogueVoice.trim();
    if (value.isNotEmpty) return value;
    return narrationVoiceFor(fallback);
  }

  TtsRoleConfig copyWith({
    bool? enabled,
    String? narrationVoice,
    String? dialogueVoice,
    List<TtsCharacterRole>? characters,
  }) {
    return TtsRoleConfig(
      enabled: enabled ?? this.enabled,
      narrationVoice: narrationVoice ?? this.narrationVoice,
      dialogueVoice: dialogueVoice ?? this.dialogueVoice,
      characters: characters ?? this.characters,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'narrationVoice': narrationVoice,
        'dialogueVoice': dialogueVoice,
        if (characters.isNotEmpty)
          'characters': [for (final character in characters) character.toMap()],
      };

  static TtsRoleConfig fromMap(Object? value) {
    if (value is! Map) return disabled;
    final characters = <TtsCharacterRole>[];
    final rawCharacters = value['characters'];
    if (rawCharacters is List) {
      for (final entry in rawCharacters) {
        final character = TtsCharacterRole.fromMap(entry);
        if (character != null) characters.add(character);
      }
    }
    return TtsRoleConfig(
      enabled: value['enabled'] == true,
      narrationVoice: _string(value['narrationVoice']),
      dialogueVoice: _string(value['dialogueVoice']),
      characters: List.unmodifiable(characters),
    );
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsRoleConfig &&
          other.enabled == enabled &&
          other.narrationVoice == narrationVoice &&
          other.dialogueVoice == dialogueVoice &&
          listEquals(other.characters, characters);

  @override
  int get hashCode => Object.hash(
        enabled,
        narrationVoice,
        dialogueVoice,
        Object.hashAll(characters),
      );
}

/// Per-book delta over [TtsRoleConfig]. Null fields follow the global value, so
/// changing the default later still reaches books that only override one voice.
@immutable
class TtsRoleBookOverride {
  const TtsRoleBookOverride({
    this.enabled,
    this.narrationVoice,
    this.dialogueVoice,
  });

  final bool? enabled;
  final String? narrationVoice;
  final String? dialogueVoice;

  bool get isEmpty =>
      enabled == null && narrationVoice == null && dialogueVoice == null;

  /// Merge this override on top of [global].
  TtsRoleConfig resolve(TtsRoleConfig global) {
    if (isEmpty) return global;
    return global.copyWith(
      enabled: enabled,
      narrationVoice: narrationVoice,
      dialogueVoice: dialogueVoice,
    );
  }

  Map<String, dynamic> toMap() => {
        if (enabled != null) 'enabled': enabled,
        if (narrationVoice != null) 'narrationVoice': narrationVoice,
        if (dialogueVoice != null) 'dialogueVoice': dialogueVoice,
      };

  static TtsRoleBookOverride fromMap(Object? value) {
    if (value is! Map) return const TtsRoleBookOverride();
    final enabled = value['enabled'];
    final narration = value['narrationVoice'];
    final dialogue = value['dialogueVoice'];
    return TtsRoleBookOverride(
      enabled: enabled is bool ? enabled : null,
      narrationVoice: narration is String ? narration.trim() : null,
      dialogueVoice: dialogue is String ? dialogue.trim() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsRoleBookOverride &&
          other.enabled == enabled &&
          other.narrationVoice == narrationVoice &&
          other.dialogueVoice == dialogueVoice;

  @override
  int get hashCode => Object.hash(enabled, narrationVoice, dialogueVoice);
}
