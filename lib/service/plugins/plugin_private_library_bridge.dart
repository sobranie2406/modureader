import 'package:flutter/material.dart';
import 'package:modu_reader/dao/book.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/page/settings_page/private_library_page.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/private_library.dart';

typedef PrivateLibraryBookPicker = Future<List<Book>?> Function(
    {required bool Function() isCurrent,
    bool? privateOnly,
    required bool multiple,
    required int limit});

/// Grants belong to one invocation and one native authentication session.
class PluginPrivateLibraryBridge {
  PluginPrivateLibraryBridge(
      {required this.context,
      required this.host,
      required this.pluginId,
      required this.isCurrent,
      this.book,
      PrivateLibrary? library,
      PrivateLibraryBookPicker? pickBooks,
      Future<Book> Function(int)? readBook})
      : library = library ?? PrivateLibrary.instance,
        _manifest = host.manifestFor(pluginId),
        _pickBooks = pickBooks,
        _readBook = readBook ?? bookDao.selectBookById;

  final BuildContext context;
  final PluginHost host;
  final String pluginId;
  final bool Function() isCurrent;
  final Book? book;
  final PrivateLibrary library;
  final PluginManifest? _manifest;
  final PrivateLibraryBookPicker? _pickBooks;
  final Future<Book> Function(int) _readBook;
  final _grants = <int, Book>{};
  final _exposed = <Book>[];
  final _revocation = ValueNotifier<bool>(false);
  int? _session;
  bool _disposed = false;
  bool _didCommit = false;
  bool _privateDataExposed = false;

  Iterable<Book> get exposedBooks => List.unmodifiable(_exposed);
  bool get canReadExposedData {
    if (_exposed.any(library.isPrivate)) _privateDataExposed = true;
    return !_privateDataExposed ||
        (!_disposed &&
            _session != null &&
            library.isAuthenticationCurrent(_session!));
  }

  bool get didCommit => _didCommit;

  bool _current() =>
      !_disposed &&
      context.mounted &&
      isCurrent() &&
      identical(_manifest, host.manifestFor(pluginId)) &&
      host.isScriptRunnable(pluginId) &&
      (_manifest?.capabilities
              .containsAll({'library:private', 'library:private-control'}) ??
          false) &&
      library.active &&
      !library.corrupt;

  bool _authenticated() =>
      _current() &&
      _session != null &&
      library.isAuthenticationCurrent(_session!);

  void _check() {
    if (!_current()) throw const PluginScriptFailure('cancelled');
  }

  void _checkAuthentication() {
    if (!_authenticated()) throw const PluginScriptFailure('cancelled');
  }

  Future<void> _authenticate() async {
    _check();
    if (_session != null) {
      _checkAuthentication();
      return;
    }
    if (!await library.requestUnlock(context,
        isCurrent: _current,
        invalidation: Listenable.merge([host, _revocation]))) {
      throw const PluginScriptFailure('cancelled');
    }
    _check();
    if (!library.unlocked) throw const PluginScriptFailure('cancelled');
    _session = library.authenticationSession;
    final bound = book;
    if (bound != null && bound.id > 0 && !bound.isDeleted) {
      _grants[bound.id] = bound.copyWith();
    }
  }

  Map<String, Object?> _state() => {
        ...library.pluginState,
        ...library.policyOptionsFor(host.development ? host : null),
      };

  Future<Object?> call(String method, Map<String, dynamic> args) async {
    _check();
    switch (method) {
      case 'privateLibrary.state':
        if (args.isNotEmpty) throw const PluginScriptFailure('permission');
        return _state();
      case 'privateLibrary.updateOptions':
        if (args.isEmpty ||
            args.keys.any((key) => !{
                  'privateOnly',
                  'autoImport',
                  'lockAfterHide'
                }.contains(key)) ||
            args.values.any((value) => value is! bool)) {
          throw const PluginScriptFailure('permission');
        }
        await _authenticate();
        if (host.development) {
          library.setOptionsOverlay(
              host,
              {
                ...library.policyOptionsFor(host),
                for (final entry in args.entries)
                  entry.key: entry.value as bool,
              },
              isCurrent: _authenticated);
        } else {
          await library.setOptions(
              privateOnly: args['privateOnly'] as bool?,
              autoImport: args['autoImport'] as bool?,
              lockAfterHide: args['lockAfterHide'] as bool?,
              isCurrent: _authenticated);
        }
        _checkAuthentication();
        return _state();
      case 'privateLibrary.selectBooks':
        if (args.keys.any(
                (key) => !{'private', 'multiple', 'limit'}.contains(key)) ||
            (args.containsKey('private') && args['private'] is! bool) ||
            (args.containsKey('multiple') && args['multiple'] is! bool) ||
            (args.containsKey('limit') && args['limit'] is! int)) {
          throw const PluginScriptFailure('permission');
        }
        final multiple = args['multiple'] as bool? ?? true;
        final limit = args['limit'] as int? ?? 100;
        if (limit < 1 || limit > 100) {
          throw const PluginScriptFailure('permission');
        }
        await _authenticate();
        if (!context.mounted) throw const PluginScriptFailure('cancelled');
        final selected = _pickBooks != null
            ? await _pickBooks(
                isCurrent: _authenticated,
                privateOnly: args['private'] as bool?,
                multiple: multiple,
                limit: multiple ? limit : 1)
            : await selectPrivateLibraryBooks(context,
                library: library,
                isCurrent: _authenticated,
                owner: Listenable.merge([host, _revocation]),
                privateOnly: args['private'] as bool?,
                multiple: multiple,
                limit: multiple ? limit : 1);
        _checkAuthentication();
        if (selected == null) return <Map<String, Object?>>[];
        if (selected.length > (multiple ? limit : 1) ||
            selected.any((item) => item.id <= 0 || item.isDeleted) ||
            selected.map((item) => item.id).toSet().length != selected.length) {
          throw const PluginScriptFailure('permission');
        }
        for (final selectedBook in selected) {
          _grants[selectedBook.id] = selectedBook.copyWith();
          _exposed.add(selectedBook.copyWith());
          if (library.isPrivate(selectedBook)) _privateDataExposed = true;
        }
        return [
          for (final selectedBook in selected)
            {
              'id': selectedBook.id,
              'title': selectedBook.title,
              'author': selectedBook.author,
              'private': library.isPrivate(selectedBook),
            }
        ];
      case 'privateLibrary.setPrivate':
        final ids = args['bookIds'];
        if (args.keys.any(
                (key) => !{'bookIds', 'private', 'lockAfter'}.contains(key)) ||
            ids is! List ||
            ids.isEmpty ||
            ids.length > 100 ||
            ids.any((id) => id is! int || id <= 0) ||
            ids.toSet().length != ids.length ||
            args['private'] is! bool ||
            (args.containsKey('lockAfter') && args['lockAfter'] is! bool)) {
          throw const PluginScriptFailure('permission');
        }
        await _authenticate();
        if (ids.any((id) => !_grants.containsKey(id))) {
          throw const PluginScriptFailure('permission');
        }
        final books = <Book>[];
        for (final id in ids.cast<int>()) {
          final current = await _readBook(id);
          _checkAuthentication();
          final granted = _grants[id]!;
          if (current.isDeleted ||
              current.id != granted.id ||
              current.md5 != granted.md5 ||
              current.filePath != granted.filePath) {
            throw const PluginScriptFailure('permission');
          }
          books.add(current);
        }
        await library.setBooksPrivate(books, args['private'] as bool,
            isCurrent: _authenticated);
        _checkAuthentication();
        _didCommit = true;
        if (args['lockAfter'] == true) library.lock();
        return {'updated': books.length};
      default:
        throw const PluginScriptFailure('permission');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _grants.clear();
    _revocation.value = true;
    _revocation.dispose();
  }
}
