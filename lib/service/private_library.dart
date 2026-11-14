import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/page/settings_page/private_library_page.dart';
import 'package:modu_reader/providers/reading_data_revision.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local access policy. Plugin code never handles credentials or files.
class PrivateLibrary extends ChangeNotifier with WidgetsBindingObserver {
  PrivateLibrary({SharedPreferences? preferences}) : _injected = preferences;

  static final instance = PrivateLibrary();
  static const storageKey = 'privateLibrary_v1';
  final SharedPreferences? _injected;
  SharedPreferences? _loaded;
  Map<String, dynamic> _config = {};
  Set<String> _private = {};
  Set<String> _protectedHistories = {};
  bool _active = false, _unlocked = false, _corrupt = false;
  bool _observing = false;
  int revision = 0, _session = 0;
  Future<void> _writes = Future.value();
  final _password =
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 210000, bits: 256);

  bool get _storageReady => _injected != null || Prefs.isReady;

  void _load() {
    if (!_storageReady) return;
    SharedPreferences prefs;
    try {
      prefs = _injected ?? Prefs().prefs;
    } catch (_) {
      return;
    }
    if (identical(_loaded, prefs)) return;
    _loaded = prefs;
    _unlocked = false;
    _config = {};
    _private = {};
    _protectedHistories = {};
    _corrupt = false;
    final raw = prefs.getString(storageKey);
    if (raw == null) return;
    try {
      final value = jsonDecode(raw);
      if (value is! Map ||
          value['books'] is! List ||
          (value['books'] as List).any((v) =>
              v is! String ||
              v.length <= 2 ||
              (!v.startsWith('m:') && !v.startsWith('f:')))) {
        throw const FormatException();
      }
      _config = Map<String, dynamic>.from(value);
      _private = Set<String>.from(value['books'] as List);
      final histories = value['histories'];
      if (histories != null &&
          (histories is! List || histories.any((v) => v is! String))) {
        throw const FormatException();
      }
      _protectedHistories = Set<String>.from(histories as List? ?? []);
      final salt = _config['salt'], hash = _config['hash'];
      if ((salt != null || hash != null) &&
          (salt is! String ||
              hash is! String ||
              base64Decode(salt).length != 16 ||
              base64Decode(hash).length != 32)) {
        throw const FormatException();
      }
    } catch (_) {
      // A damaged protection record must not silently expose the library.
      _corrupt = true;
    }
  }

  bool get active {
    _load();
    return _active;
  }

  bool get unlocked {
    _load();
    return _storageReady && _unlocked;
  }

  bool get hasPin {
    _load();
    return _config['hash'] is String;
  }

  bool get corrupt {
    _load();
    return _corrupt || (_active && !_storageReady);
  }

  bool get hasPrivateBooks {
    _load();
    return _private.isNotEmpty;
  }

  bool get showEntry => active;
  bool get enabled {
    _load();
    return _config['enabled'] != false;
  }

  bool get privateOnly {
    _load();
    return _config['privateOnly'] == true;
  }

  bool get autoImport {
    _load();
    return _config['autoImport'] == true;
  }

  String _identity(Book book) => book.md5?.isNotEmpty == true
      ? 'm:${book.md5!.toLowerCase()}'
      : 'f:${book.filePath}';

  bool isPrivate(Book book) {
    _load();
    return _private.contains(_identity(book));
  }

  bool canRead(Book book) =>
      !corrupt && (!enabled || !isPrivate(book) || unlocked);
  bool isVisible(Book book) =>
      canRead(book) &&
      (!enabled || !unlocked || !privateOnly || isPrivate(book));

  bool canReadHistory(String id, {bool unscoped = false}) =>
      !corrupt &&
      (!enabled ||
          unlocked ||
          (!_protectedHistories.contains(id) &&
              !(unscoped && hasPrivateBooks)));

  Future<void> protectHistory(String id) {
    _load();
    if (id.isEmpty || !_protectedHistories.add(id)) return Future.value();
    _changed();
    return _save(() => {
          ..._config,
          'books': _private.toList(),
          'histories': _protectedHistories.toList()
        });
  }

  /// Used only by presentation queries, never by synchronization or backups.
  String bookPredicate([String alias = '']) {
    _load();
    if (corrupt) return '0';
    if (!enabled) return '1';
    if (_unlocked && !privateOnly) return '1';
    if (_private.isEmpty) return _unlocked && privateOnly ? '0' : '1';
    assert(
        alias.isEmpty || RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(alias));
    final prefix = alias.isEmpty ? '' : '$alias.';
    String quote(String v) => "'${v.replaceAll("'", "''")}'";
    final hashes = _private
        .where((v) => v.startsWith('m:'))
        .map((v) => quote(v.substring(2)))
        .toList();
    final files = _private
        .where((v) => v.startsWith('f:'))
        .map((v) => quote(v.substring(2)))
        .toList();
    final marked = [
      if (hashes.isNotEmpty)
        "lower(${prefix}file_md5) IN (${hashes.join(',')})",
      if (files.isNotEmpty) "${prefix}file_path IN (${files.join(',')})",
    ].join(' OR ');
    return _unlocked && privateOnly
        ? '($marked)'
        : 'NOT (COALESCE(($marked), 0))';
  }

  String bookIdPredicate([String column = 'book_id']) {
    final predicate = bookPredicate();
    return predicate == '1'
        ? '1'
        : '$column IN (SELECT id FROM tb_books WHERE $predicate)';
  }

  void _changed() {
    revision++;
    bumpReadingDataRevision();
    notifyListeners();
  }

  void setPluginActive(bool value) {
    if (value && !_observing) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      } catch (_) {/* Data-only callers need no application lifecycle. */}
    }
    _load();
    if (_active == value) return;
    _active = value;
    _unlocked = false;
    _session++;
    _changed();
  }

  void lock() {
    _load();
    _session++;
    if (!_unlocked) return;
    _unlocked = false;
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      lock();
    }
  }

  void _checkSession(int session) {
    if (!unlocked || session != _session) {
      throw StateError('Private library locked');
    }
  }

  Future<void> _save(Map<String, dynamic> Function() transform,
      {int? session}) {
    _load();
    final done = _writes.then((_) async {
      if (corrupt || !_storageReady || _loaded == null) {
        throw StateError('Private library unavailable');
      }
      if (session != null) _checkSession(session);
      final next = transform();
      final previous = _loaded!.getString(storageKey);
      try {
        if (!await _loaded!.setString(storageKey, jsonEncode(next))) {
          throw StateError('Could not save private library');
        }
        if (session != null) _checkSession(session);
      } catch (_) {
        if (previous == null) {
          await _loaded!.remove(storageKey);
        } else {
          await _loaded!.setString(storageKey, previous);
        }
        rethrow;
      }
      _config = next;
      _private = Set<String>.from(next['books'] as List);
      _changed();
    });
    _writes = done.catchError((_) {});
    return done;
  }

  Future<void> setOptions({bool? privateOnly, bool? autoImport}) {
    if (!unlocked) throw StateError('Private library locked');
    return _save(
        () => {
              ..._config,
              'books': _private.toList(),
              if (privateOnly != null) 'privateOnly': privateOnly,
              if (autoImport != null) 'autoImport': autoImport
            },
        session: _session);
  }

  Future<void> setBooksPrivate(Iterable<Book> books, bool value) {
    if (!unlocked) throw StateError('Private library locked');
    final identities = books.map(_identity).toSet();
    return _save(() {
      final next = {..._private};
      value ? next.addAll(identities) : next.removeAll(identities);
      return {..._config, 'books': next.toList()};
    }, session: _session);
  }

  Future<void> setEnabled(bool value) async {
    if (!unlocked) throw StateError('Private library locked');
    await _save(
        () => {..._config, 'books': _private.toList(), 'enabled': value},
        session: _session);
    lock();
  }

  Future<void> onImported(Book book, {required bool isNew}) async {
    if (!isNew || !active || !enabled || !autoImport) return;
    await _save(() => {
          ..._config,
          'books': {..._private, _identity(book)}.toList()
        });
  }

  Future<bool> unlock([String pin = '']) async {
    _load();
    if (corrupt) return false;
    final session = _session;
    final salt = _config['salt'], hash = _config['hash'];
    if (hasPin) {
      if (!RegExp(r'^\d{6}$').hasMatch(pin)) return false;
      final key = await _password.deriveKey(
          secretKey: SecretKey(utf8.encode(pin)),
          nonce: base64Decode(salt as String));
      final actual = await key.extractBytes(),
          expected = base64Decode(hash as String);
      var difference = 0;
      for (var i = 0; i < expected.length; i++) {
        difference |= actual[i] ^ expected[i];
      }
      if (difference != 0) return false;
    }
    if (session != _session) return false;
    _unlocked = true;
    _changed();
    return true;
  }

  Future<void> setPin(String? pin) async {
    if (!unlocked) throw StateError('Private library locked');
    if (pin != null && !RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw const FormatException('Use six digits');
    }
    final session = _session;
    String? salt, hash;
    if (pin != null) {
      final random = Random.secure();
      final bytes = List.generate(16, (_) => random.nextInt(256));
      salt = base64Encode(bytes);
      hash = base64Encode(await (await _password.deriveKey(
              secretKey: SecretKey(utf8.encode(pin)), nonce: bytes))
          .extractBytes());
    }
    if (!unlocked || session != _session) {
      throw StateError('Private library locked');
    }
    await _save(
        () => {..._config, 'books': _private.toList()}
          ..remove('salt')
          ..remove('hash')
          ..addAll(
              {if (salt != null) 'salt': salt, if (hash != null) 'hash': hash}),
        session: session);
  }

  Future<bool> requestUnlock(BuildContext context, {bool force = false}) async {
    if (!active) return false;
    if (unlocked && !force) return true;
    return await showPrivateLibraryUnlock(context, this);
  }

  Future<void> open(BuildContext context) async {
    if (!active) throw StateError('Private library plugin is not enabled');
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PrivateLibraryPage(library: this)));
  }

  Future<bool> authorizeDeactivate(BuildContext context) async {
    if (!showEntry &&
        !hasPrivateBooks &&
        _protectedHistories.isEmpty &&
        !hasPin) {
      return true;
    }
    if (!await showPrivateLibraryUnlock(context, this) || !context.mounted) {
      return false;
    }
    return await showPrivateLibraryDeactivate(context) == true;
  }

  Future<void> clearProtection() async {
    if (!unlocked) throw StateError('Private library locked');
    final session = _session;
    await _save(() {
      if (!unlocked || session != _session) {
        throw StateError('Private library locked');
      }
      return {'books': <String>[]};
    }, session: session);
    _protectedHistories.clear();
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
