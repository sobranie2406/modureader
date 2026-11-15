import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:modu_reader/dao/book.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/private_library.dart';
import 'dart:async';
import 'package:modu_reader/service/tts/tts_handler.dart';

String _t(BuildContext context, String zh, String en) =>
    ModuStrings.text(context, zh, en);

Future<T?> _settledDialog<T>(
    {required BuildContext context,
    required WidgetBuilder builder,
    VoidCallback? onDismissed,
    bool Function()? isCurrent,
    Listenable? invalidation}) async {
  if (isCurrent?.call() == false) return null;
  final route = DialogRoute<T>(context: context, builder: builder);
  final navigator = Navigator.of(context, rootNavigator: true);
  void dismiss() {
    if (isCurrent?.call() == false && navigator.mounted && route.isActive) {
      try {
        navigator.removeRoute(route);
      } catch (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => dismiss());
      }
    }
  }

  invalidation?.addListener(dismiss);
  try {
    final result = await navigator.push(route);
    onDismissed?.call();
    await route.completed;
    return isCurrent?.call() == false ? null : result;
  } finally {
    invalidation?.removeListener(dismiss);
  }
}

Future<bool> showPrivateLibraryUnlock(
    BuildContext context, PrivateLibrary library,
    {bool Function()? isCurrent, Listenable? invalidation}) async {
  final pin = TextEditingController();
  var busy = false, failed = false, finished = false, dismissed = false;
  try {
    return await _settledDialog<bool>(
            context: context,
            isCurrent: isCurrent,
            invalidation: invalidation,
            onDismissed: () {
              dismissed = true;
              if (busy && !finished) library.cancelPendingAuthentication();
            },
            builder: (context) => StatefulBuilder(
                builder: (context, setState) => AlertDialog(
                        title: Text(
                            _t(context, '解锁私密书库', 'Unlock private library')),
                        content: library.corrupt
                            ? Text(_t(context, '私密设置无法读取，请恢复本机数据后重试。',
                                'Private settings could not be read. Restore local data and retry.'))
                            : library.hasPin
                                ? TextField(
                                    key: const ValueKey('private-library-pin'),
                                    controller: pin,
                                    autofocus: true,
                                    obscureText: true,
                                    enabled: !busy,
                                    keyboardType: TextInputType.number,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    enableIMEPersonalizedLearning: false,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(6)
                                    ],
                                    decoration: InputDecoration(
                                        labelText: _t(
                                            context, '6 位密码', 'Six-digit PIN'),
                                        errorText: failed
                                            ? _t(context, '密码错误',
                                                'Incorrect PIN')
                                            : null))
                                : Text(_t(context, '解锁后可查看私密书籍。',
                                    'Unlock to view private books.')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(_t(context, '取消', 'Cancel'))),
                          FilledButton(
                              onPressed: busy || library.corrupt
                                  ? null
                                  : () async {
                                      if (isCurrent?.call() == false) return;
                                      setState(() {
                                        busy = true;
                                        failed = false;
                                      });
                                      bool success;
                                      try {
                                        success =
                                            await library.unlock(pin.text);
                                      } catch (_) {
                                        if (!context.mounted || dismissed) {
                                          return;
                                        }
                                        setState(() => busy = false);
                                        ScaffoldMessenger.maybeOf(context)
                                            ?.showSnackBar(SnackBar(
                                                content: Text(_t(
                                                    context,
                                                    '解锁失败，请重试',
                                                    'Could not unlock. Try again.'))));
                                        return;
                                      }
                                      if (!context.mounted ||
                                          dismissed ||
                                          isCurrent?.call() == false) {
                                        return;
                                      }
                                      if (success) {
                                        finished = true;
                                        Navigator.pop(context, true);
                                      } else {
                                        setState(() {
                                          busy = false;
                                          failed = true;
                                        });
                                      }
                                    },
                              child: busy
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          semanticsLabel:
                                              _t(context, '正在解锁', 'Unlocking')))
                                  : Text(_t(context, '解锁', 'Unlock')))
                        ]))) ??
        false;
  } finally {
    pin.dispose();
  }
}

Future<bool?> showPrivateLibraryDeactivate(BuildContext context) => showDialog<
        bool>(
    context: context,
    builder: (context) => AlertDialog(
            title: Text(_t(context, '停用私密书库', 'Disable private library')),
            content: Text(_t(context, '停用后，私密书籍恢复为普通书籍，并按当前设置参与同步。书籍、笔记和进度会保留。',
                'Disabling makes private books ordinary books that follow your sync settings. Books, notes and progress are kept.')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(_t(context, '取消', 'Cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(_t(context, '停用', 'Disable')))
            ]));

class PrivateLibrarySettings extends StatelessWidget {
  const PrivateLibrarySettings(
      {super.key,
      required this.library,
      this.embedded = false,
      this.showPolicyOptions = true,
      this.optionsOwner});
  final PrivateLibrary library;
  final bool embedded;
  final bool showPolicyOptions;
  final Object? optionsOwner;

  Future<void> _saveOptions({bool? privateOnly, bool? autoImport}) async {
    final owner = optionsOwner;
    if (owner == null) {
      await library.setOptions(
          privateOnly: privateOnly, autoImport: autoImport);
    } else {
      library.setOptionsOverlay(owner, {
        ...library.policyOptionsFor(owner),
        if (privateOnly != null) 'privateOnly': privateOnly,
        if (autoImport != null) 'autoImport': autoImport,
      });
    }
  }

  Widget _body(List<Widget> children, {EdgeInsetsGeometry? padding}) => embedded
      ? Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children))
      : ListView(padding: padding, children: children);

  Future<void> _setPin(BuildContext context) async {
    final pin = TextEditingController(), repeat = TextEditingController();
    var failed = false, busy = false, finished = false, dismissed = false;
    try {
      await _settledDialog<void>(
          context: context,
          onDismissed: () {
            dismissed = true;
            if (busy && !finished) library.cancelPendingAuthentication();
          },
          builder: (context) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                      title: Text(_t(context, '设置 6 位密码', 'Set six-digit PIN')),
                      content:
                          Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final controller in [pin, repeat])
                          TextField(
                              controller: controller,
                              enabled: !busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              enableIMEPersonalizedLearning: false,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6)
                              ],
                              decoration: InputDecoration(
                                  labelText: controller == pin
                                      ? _t(context, '新密码', 'New PIN')
                                      : _t(context, '再次输入', 'Repeat PIN'),
                                  errorText: failed
                                      ? _t(context, '请输入相同的 6 位密码',
                                          'Enter the same six-digit PIN')
                                      : null))
                      ]),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(_t(context, '取消', 'Cancel'))),
                        FilledButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    if (!RegExp(r'^\d{6}$')
                                            .hasMatch(pin.text) ||
                                        pin.text != repeat.text) {
                                      setState(() => failed = true);
                                      return;
                                    }
                                    setState(() => busy = true);
                                    try {
                                      await library.setPin(pin.text);
                                      if (context.mounted && !dismissed) {
                                        finished = true;
                                        Navigator.pop(context);
                                      }
                                    } catch (_) {
                                      if (context.mounted && !dismissed) {
                                        setState(() => busy = false);
                                        _failure(context);
                                      }
                                    }
                                  },
                            child: busy
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        semanticsLabel:
                                            _t(context, '正在保存', 'Saving')))
                                : Text(_t(context, '保存', 'Save')))
                      ])));
    } finally {
      pin.dispose();
      repeat.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final options = library.policyOptionsFor(optionsOwner);
        if (!library.active) {
          return Center(child: Text(_t(context, '插件已停用', 'Plugin disabled')));
        }
        final enabled = SwitchListTile(
            key: const ValueKey('private-library-enabled'),
            title: Text(_t(context, '私密书籍', 'Private books')),
            value: library.enabled,
            onChanged: (value) async {
              if (!await library.requestUnlock(context,
                  force: library.hasPin)) {
                return;
              }
              try {
                await library.setEnabled(value);
              } catch (_) {
                if (context.mounted) _failure(context);
              }
            });
        if (!library.enabled || !library.unlocked) {
          return _body([
            enabled,
            if (library.enabled)
              embedded
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: _PrivateLocked(library: library))
                  : SizedBox(
                      height: 240, child: _PrivateLocked(library: library))
          ]);
        }
        final authenticationActions = Wrap(children: [
          if (library.hasPin)
            TextButton(
                onPressed: () async {
                  try {
                    await library.setPin(null);
                  } catch (_) {
                    if (context.mounted) _failure(context);
                  }
                },
                child: Text(_t(context, '移除', 'Remove'))),
          TextButton(
              onPressed: () => _setPin(context),
              child: Text(_t(context, library.hasPin ? '修改' : '设置',
                  library.hasPin ? 'Change' : 'Set')))
        ]);
        Future<void> changeVisibility(bool value) async {
          try {
            await _saveOptions(privateOnly: value);
          } catch (_) {
            if (context.mounted) _failure(context);
          }
        }

        return _body(padding: const EdgeInsets.all(16), [
          enabled,
          ListTile(
              leading: const Icon(Icons.lock_open),
              title: Text(_t(context, '已解锁', 'Unlocked')),
              trailing: TextButton(
                  key: const ValueKey('private-library-lock'),
                  onPressed: library.lock,
                  child: Text(_t(context, '锁定', 'Lock')))),
          if (embedded)
            Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_t(context, '验证方式', 'Authentication')),
                      Text(_t(context, library.hasPin ? '6 位密码' : '无密码',
                          library.hasPin ? 'Six-digit PIN' : 'No PIN')),
                      authenticationActions,
                    ]))
          else
            ListTile(
                title: Text(_t(context, '验证方式', 'Authentication')),
                subtitle: Text(_t(context, library.hasPin ? '6 位密码' : '无密码',
                    library.hasPin ? 'Six-digit PIN' : 'No PIN')),
                trailing: authenticationActions),
          if (showPolicyOptions)
            ListTile(
                title: Text(_t(context, '解锁后显示', 'After unlocking')),
                subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: embedded
                        ? Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final value in [false, true])
                              ChoiceChip(
                                label: Text(_t(
                                    context,
                                    value ? '仅私密书籍' : '全部书籍',
                                    value ? 'Private only' : 'All books')),
                                selected: options['privateOnly'] == value,
                                onSelected: (_) => changeVisibility(value),
                              ),
                          ])
                        : SegmentedButton<bool>(
                            segments: [
                                ButtonSegment(
                                    value: false,
                                    label:
                                        Text(_t(context, '全部书籍', 'All books'))),
                                ButtonSegment(
                                    value: true,
                                    label: Text(
                                        _t(context, '仅私密书籍', 'Private only')))
                              ],
                            selected: {
                                options['privateOnly']!
                              },
                            onSelectionChanged: (v) =>
                                changeVisibility(v.single)))),
          if (showPolicyOptions)
            SwitchListTile(
                value: options['autoImport']!,
                title:
                    Text(_t(context, '新导入书籍设为私密', 'Make new imports private')),
                onChanged: (v) async {
                  try {
                    await _saveOptions(autoImport: v);
                  } catch (_) {
                    if (context.mounted) _failure(context);
                  }
                }),
          if (showPolicyOptions)
            ListTile(
                leading: const Icon(Icons.library_books_outlined),
                title: Text(_t(context, '管理私密书籍', 'Manage private books')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => _PrivateBooksPage(library: library)))),
        ]);
      });
}

class PrivateLibraryPage extends StatelessWidget {
  const PrivateLibraryPage(
      {super.key,
      required this.library,
      this.showPolicyOptions = true,
      this.optionsOwner});
  final PrivateLibrary library;
  final bool showPolicyOptions;
  final Object? optionsOwner;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(_t(context, '私密书库', 'Private library'))),
      body: PrivateLibrarySettings(
          library: library,
          showPolicyOptions: showPolicyOptions,
          optionsOwner: optionsOwner));
}

void _failure(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_t(context, '未能保存，请重试', 'Could not save. Try again.'))));

class _PrivateLocked extends StatelessWidget {
  const _PrivateLocked({required this.library});
  final PrivateLibrary library;
  @override
  Widget build(BuildContext context) => Center(
      child: !library.active
          ? Text(_t(context, '书籍暂不可访问，请启用对应插件。',
              'Book unavailable. Enable its plugin first.'))
          : FilledButton.icon(
              key: const ValueKey('private-library-unlock'),
              icon: const Icon(Icons.lock_outline),
              onPressed: () => library.requestUnlock(context),
              label: Text(_t(context, '解锁私密书库', 'Unlock private library'))));
}

Future<List<Book>?> selectPrivateLibraryBooks(BuildContext context,
    {required PrivateLibrary library,
    required bool Function() isCurrent,
    Listenable? owner,
    bool? privateOnly,
    bool multiple = true,
    int limit = 100,
    Future<List<Book>> Function()? loadBooks}) async {
  final session = library.authenticationSession;
  bool current() =>
      context.mounted &&
      isCurrent() &&
      library.active &&
      !library.corrupt &&
      library.isAuthenticationCurrent(session);
  if (!current()) return null;
  final navigator = Navigator.of(context);
  late MaterialPageRoute<List<Book>> route;
  void dismiss() {
    if (!current() && navigator.mounted && route.isActive) {
      try {
        navigator.removeRoute(route);
      } catch (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => dismiss());
      }
    }
  }

  route = MaterialPageRoute<List<Book>>(
      builder: (_) => _PrivateBookPicker(
          library: library,
          current: current,
          owner: owner,
          privateOnly: privateOnly,
          multiple: multiple,
          limit: limit,
          loadBooks: loadBooks ?? bookDao.selectNotDeleteBooks));
  library.addListener(dismiss);
  owner?.addListener(dismiss);
  try {
    final selected = await navigator.push(route);
    await route.completed;
    return current() ? selected : null;
  } finally {
    library.removeListener(dismiss);
    owner?.removeListener(dismiss);
  }
}

class _PrivateBookPicker extends StatefulWidget {
  const _PrivateBookPicker(
      {required this.library,
      required this.current,
      required this.owner,
      required this.privateOnly,
      required this.multiple,
      required this.limit,
      required this.loadBooks});
  final PrivateLibrary library;
  final bool Function() current;
  final Listenable? owner;
  final bool? privateOnly;
  final bool multiple;
  final int limit;
  final Future<List<Book>> Function() loadBooks;
  @override
  State<_PrivateBookPicker> createState() => _PrivateBookPickerState();
}

class _PrivateBookPickerState extends State<_PrivateBookPicker> {
  late final _books = widget.loadBooks();
  final _selected = <int>{};
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([widget.library, widget.owner]),
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(_t(context, '选择书籍', 'Select books'))),
          body: !widget.current()
              ? const SizedBox.shrink()
              : FutureBuilder<List<Book>>(
                  future: _books,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                          child: Text(
                              _t(context, '无法读取书架', 'Could not load books')));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final books = snapshot.data!
                        .where((book) =>
                            !book.isDeleted &&
                            book.id > 0 &&
                            (widget.privateOnly == null ||
                                widget.library.isPrivate(book) ==
                                    widget.privateOnly))
                        .toList();
                    return Column(children: [
                      Expanded(
                          child: ListView.builder(
                              itemCount: books.length,
                              itemBuilder: (context, index) {
                                final book = books[index];
                                return CheckboxListTile(
                                    key: ValueKey('private-select-${book.id}'),
                                    title: Text(book.title),
                                    subtitle: Text(book.author),
                                    value: _selected.contains(book.id),
                                    onChanged: (selected) {
                                      if (!widget.current()) return;
                                      setState(() {
                                        if (selected != true) {
                                          _selected.remove(book.id);
                                        } else if (!widget.multiple) {
                                          _selected
                                            ..clear()
                                            ..add(book.id);
                                        } else if (_selected.length <
                                            widget.limit) {
                                          _selected.add(book.id);
                                        }
                                      });
                                    });
                              })),
                      SafeArea(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: FilledButton(
                                  key: const ValueKey('private-select-confirm'),
                                  onPressed: _selected.isEmpty
                                      ? null
                                      : () {
                                          if (widget.current()) {
                                            Navigator.pop(
                                                context,
                                                books
                                                    .where((book) => _selected
                                                        .contains(book.id))
                                                    .toList());
                                          }
                                        },
                                  child: Text(_t(context, '确定', 'Confirm'))))),
                    ]);
                  })));
}

class _PrivateBooksPage extends StatefulWidget {
  const _PrivateBooksPage({required this.library});
  final PrivateLibrary library;
  @override
  State<_PrivateBooksPage> createState() => _PrivateBooksPageState();
}

class _PrivateBooksPageState extends State<_PrivateBooksPage> {
  late final _books = bookDao.selectNotDeleteBooks();
  final _selected = <int>{};
  bool _saving = false;
  Future<void> _mark(List<Book> books, bool value) async {
    setState(() => _saving = true);
    try {
      await widget.library.setBooksPrivate(books, value);
      if (mounted) setState(_selected.clear);
    } catch (_) {
      if (mounted) _failure(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar:
          AppBar(title: Text(_t(context, '管理私密书籍', 'Manage private books'))),
      body: ListenableBuilder(
          listenable: widget.library,
          builder: (context, _) {
            if (!widget.library.active || !widget.library.unlocked) {
              return _PrivateLocked(library: widget.library);
            }
            return FutureBuilder<List<Book>>(
                future: _books,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                        child: Text(
                            _t(context, '无法读取书架', 'Could not load books')));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final books = snapshot.data!;
                  final selected =
                      books.where((b) => _selected.contains(b.id)).toList();
                  return Column(children: [
                    if (books.isNotEmpty)
                      CheckboxListTile(
                          title: Text(_t(context, '全选', 'Select all')),
                          value: _selected.length == books.length,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() {
                                    _selected.clear();
                                    if (v == true) {
                                      _selected.addAll(books.map((b) => b.id));
                                    }
                                  })),
                    if (selected.isNotEmpty)
                      Wrap(spacing: 12, children: [
                        FilledButton(
                            onPressed:
                                _saving ? null : () => _mark(selected, true),
                            child: Text(_t(context, '设为私密', 'Make private'))),
                        TextButton(
                            onPressed:
                                _saving ? null : () => _mark(selected, false),
                            child: Text(_t(context, '取消私密', 'Make public')))
                      ]),
                    Expanded(
                        child: ListView.builder(
                            itemCount: books.length,
                            itemBuilder: (context, index) {
                              final book = books[index];
                              return CheckboxListTile(
                                  value: _selected.contains(book.id),
                                  onChanged: _saving
                                      ? null
                                      : (v) => setState(() {
                                            v == true
                                                ? _selected.add(book.id)
                                                : _selected.remove(book.id);
                                          }),
                                  title: Text(book.title),
                                  subtitle: Text(book.author),
                                  secondary: IconButton(
                                      tooltip: _t(
                                          context,
                                          widget.library.isPrivate(book)
                                              ? '取消私密'
                                              : '设为私密',
                                          widget.library.isPrivate(book)
                                              ? 'Make public'
                                              : 'Make private'),
                                      icon: Icon(widget.library.isPrivate(book)
                                          ? Icons.lock
                                          : Icons.lock_open),
                                      onPressed: _saving
                                          ? null
                                          : () => _mark(
                                              [book],
                                              !widget.library
                                                  .isPrivate(book))));
                            })),
                  ]);
                });
          }));
}

/// Rechecks a mounted route too, so background locking removes readable content.
class PrivateBookGate extends StatefulWidget {
  const PrivateBookGate(
      {super.key,
      required this.book,
      required this.builder,
      this.reader = false});
  final Book book;
  final WidgetBuilder builder;
  final bool reader;
  @override
  State<PrivateBookGate> createState() => _PrivateBookGateState();
}

class _PrivateBookGateState extends State<PrivateBookGate> {
  ModalRoute<dynamic>? _owner;
  late bool _readable;
  @override
  void initState() {
    super.initState();
    _readable = PrivateLibrary.instance.canRead(widget.book);
    PrivateLibrary.instance.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _owner = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(covariant PrivateBookGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _readable = PrivateLibrary.instance.canRead(widget.book);
  }

  void _changed() {
    final readable = PrivateLibrary.instance.canRead(widget.book);
    if (_readable && !readable) {
      if (widget.reader) {
        final handler = TtsHandler();
        if (handler.mediaItem.value?.id == widget.book.id.toString()) {
          handler.mediaItem.add(null);
          handler.queue.add([]);
          unawaited(handler.stop().catchError((_) {}));
        }
      }
      void closeDerivedRoutes() {
        final owner = _owner;
        if (mounted && owner?.isActive == true && owner?.navigator != null) {
          owner!.navigator!.popUntil((route) => identical(route, owner));
        }
      }

      try {
        closeDerivedRoutes();
      } catch (_) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => closeDerivedRoutes());
      }
    }
    _readable = readable;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PrivateLibrary.instance.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(
          BuildContext context) =>
      PrivateLibrary.instance.canRead(widget.book)
          ? widget.builder(context)
          : Scaffold(
              appBar: AppBar(title: Text(_t(context, '私密书籍', 'Private book'))),
              body: _PrivateLocked(library: PrivateLibrary.instance));
}
