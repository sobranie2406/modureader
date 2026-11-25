import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/remote_library/ftp_connection.dart';
import 'package:modu_reader/service/remote_library/ftp_library.dart';
import 'package:modu_reader/service/remote_library/webdav_library.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/widgets/common/anx_segmented_button.dart';
import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:flutter/material.dart';

class RemoteLibrarySettings extends StatefulWidget {
  const RemoteLibrarySettings({
    super.key,
    this.initialSource = RemoteLibrarySource.webdav,
  });

  final RemoteLibrarySource initialSource;

  @override
  State<RemoteLibrarySettings> createState() => _RemoteLibrarySettingsState();
}

class _RemoteLibrarySettingsState extends State<RemoteLibrarySettings> {
  final _url = TextEditingController();
  final _directory = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  late RemoteLibrarySource _source = widget.initialSource;
  bool _loading = true, _busy = false, _http = false, _hide = true;
  String? _message;
  RemoteLibrary? _testing;
  bool get _isFtp => _source == RemoteLibrarySource.ftp;
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String cn, String en) => ModuStrings.text(context, cn, en);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final webdav = _isFtp ? null : await LibraryConnectionStore.load();
    final ftp = _isFtp ? await FtpConnectionStore.load() : null;
    if (!mounted) return;
    setState(() {
      _url.text = ftp?.address ?? webdav?.url ?? '';
      _directory.text = ftp?.directory ?? '';
      _username.text = ftp?.username ?? webdav?.username ?? '';
      _password.text = ftp?.password ?? webdav?.password ?? '';
      _http = webdav?.allowHttp ?? false;
      _hide = true;
      _loading = false;
    });
  }

  Future<void> _selectSource(RemoteLibrarySource source) async {
    if (_source == source) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _source = source;
      _loading = true;
      _message = null;
    });
    await _load();
  }

  Future<void> _testConnection(RemoteLibrary client) async {
    _testing = client;
    try {
      await client.list(client.root);
    } finally {
      client.close();
      _testing = null;
    }
  }

  Future<void> _perform(bool save) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_isFtp) {
        final value = FtpConnection(
          address: _url.text,
          directory: _directory.text,
          username: _username.text.trim(),
          password: _password.text,
        );
        final Uri root;
        try {
          root = value.root;
        } on FormatException {
          setState(() => _message = t('请检查 FTP 地址、目录和登录信息。',
              'Check the FTP address, directory and login details.'));
          return;
        }
        if (save) {
          await FtpConnectionStore.save(value);
        } else {
          await _testConnection(FtpLibrary(root,
              username: value.username, password: value.password));
        }
      } else {
        final value = LibraryConnection(
          url: _url.text,
          username: _username.text.trim(),
          password: _password.text,
          allowHttp: _http,
        );
        if (save) {
          await LibraryConnectionStore.save(value);
        } else {
          await _testConnection(WebdavLibrary(value));
        }
      }
      if (mounted) {
        setState(() => _message = save
            ? ModuStrings.text(context, "连接已保存，请到“远程书库”打开。",
                "Connection saved. Open Remote library to browse.")
            : t('连接成功，目录可读取。', 'Connected. The directory is readable.'));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = _isFtp
            ? ftpLibraryError(error, zh, listing: !save)
            : libraryError(error, zh));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearConnection() async {
    final confirmed = await showDialog<bool>(
      animationStyle: AppMotion.style,
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('清除书库连接？', 'Clear library connection?')),
        content: Text(_isFtp
            ? t('清除本机保存的 FTP 连接和密码？',
                'Clear the FTP connection and password on this device?')
            : t('清除连接和密码？开启同步的设备也会更新。',
                'Clear the connection and password? This also updates devices with sync enabled.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('清除', 'Clear'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (_isFtp) {
        await FtpConnectionStore.clear();
      } else {
        await LibraryConnectionStore.clear();
      }
      if (!mounted) return;
      await _load();
      if (mounted) {
        setState(() => _message =
            t('已清除连接配置和保存的密码。', 'Connection and saved password cleared.'));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message =
            _isFtp ? ftpLibraryError(error, zh) : libraryError(error, zh));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _testing?.close();
    _url.dispose();
    _directory.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: EinkStaticIndicator(child: CircularProgressIndicator()));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: AnxSegmentedButton<RemoteLibrarySource>(
          segments: [
            for (final source in RemoteLibrarySource.values)
              SegmentButtonItem(value: source, label: source.label),
          ],
          selected: {_source},
          onSelectionChanged:
              _busy ? null : (value) => _selectSource(value.single),
        ),
      ),
      SettingsSection.content(
        key: const ValueKey('remote-library-settings-frame'),
        title: _isFtp
            ? SettingHelpTitle(
                title: t('连接配置', 'Connection settings'),
                description: t('FTP 会明文传输帐号、密码和文件，请在可信的局域网内使用。',
                    'FTP sends login details and files unencrypted. Use it on a trusted local network.'),
              )
            : Text(t('连接配置', 'Connection settings')),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
                controller: _url,
                enabled: !_busy,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                    labelText: _isFtp
                        ? t('FTP 地址', 'FTP address')
                        : t('WebDAV 书库完整地址', 'Full WebDAV library URL'),
                    hintText: _isFtp
                        ? '192.168.1.1:21'
                        : 'https://example.com/dav/books/',
                    border: const OutlineInputBorder())),
            if (_isFtp) ...[
              const SizedBox(height: 16),
              TextField(
                  controller: _directory,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: InputDecoration(
                      labelText: t('目录', 'Directory'),
                      hintText: '/',
                      border: const OutlineInputBorder())),
            ],
            const SizedBox(height: 16),
            TextField(
                controller: _username,
                enabled: !_busy,
                autocorrect: false,
                decoration: InputDecoration(
                    labelText: ModuStrings.text(context, '用户名（匿名访问可留空）',
                        'Username (optional for anonymous access)'),
                    border: const OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: _hide,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                    labelText: ModuStrings.text(context, '密码（保存在本机）',
                        'Password (saved on this device)'),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                        tooltip: ModuStrings.text(
                            context, '显示或隐藏密码', 'Show or hide password'),
                        onPressed: () => setState(() => _hide = !_hide),
                        icon: Icon(_hide
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined)))),
          ],
        ),
      ),
      if (!_isFtp)
        SettingsSection.content(
          title: Text(ModuStrings.text(context, '连接安全', 'Connection security')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _http,
                  onChanged: _busy ? null : (v) => setState(() => _http = v),
                  title: Text(ModuStrings.text(
                      context, '允许 HTTP 明文连接', 'Allow unencrypted HTTP')),
                  subtitle: SettingHelp(
                      title:
                          Text(ModuStrings.text(context, "连接方式", "Connection")),
                      description: Text(ModuStrings.text(
                          context,
                          "建议使用 HTTPS 连接。",
                          "Use HTTPS for this connection.")))),
              SettingHelp(
                  title: Text(
                      ModuStrings.text(context, "同步连接", "Sync connection")),
                  description: Text(ModuStrings.text(
                      context,
                      "在“同步”中开启敏感数据同步，可同步书库连接。",
                      "Enable Sensitive data sync in Sync settings to share this connection."))),
            ],
          ),
        ),
      SettingsSection.content(
        title: Text(ModuStrings.text(context, '连接管理', 'Connection management')),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              OutlinedButton.icon(
                  onPressed: _busy ? null : () => _perform(false),
                  icon: const Icon(Icons.wifi_tethering),
                  label: Text(
                      ModuStrings.text(context, '测试连接', 'Test connection'))),
              FilledButton.icon(
                  onPressed: _busy ? null : () => _perform(true),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(ModuStrings.text(context, '保存配置', 'Save'))),
              TextButton(
                  onPressed: _busy ? null : _clearConnection,
                  child: Text(
                      ModuStrings.text(context, '清除连接', 'Clear connection'))),
            ]),
            if (_busy)
              const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: EinkStaticIndicator(child: LinearProgressIndicator())),
            if (_message != null)
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_message!)),
          ],
        ),
      ),
    ]);
  }
}
