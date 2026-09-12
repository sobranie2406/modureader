import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:anx_reader/service/config_transfer/library_config_transfer.dart';
import 'package:anx_reader/widgets/settings/config_transfer_tile.dart';
import 'package:flutter/material.dart';

class RemoteLibrarySettings extends StatefulWidget {
  const RemoteLibrarySettings({super.key});
  @override
  State<RemoteLibrarySettings> createState() => _RemoteLibrarySettingsState();
}

class _RemoteLibrarySettingsState extends State<RemoteLibrarySettings> {
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = true, _busy = false, _http = false, _hide = true;
  String? _message;
  WebdavLibrary? _testing;
  bool _exportPassword = true;
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String cn, String en) => zh ? cn : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await LibraryConnectionStore.load();
    if (!mounted) return;
    setState(() {
      _url.text = value?.url ?? '';
      _username.text = value?.username ?? '';
      _password.text = value?.password ?? '';
      _http = value?.allowHttp ?? false;
      _loading = false;
    });
  }

  LibraryConnection get _value => LibraryConnection(
      url: _url.text,
      username: _username.text.trim(),
      password: _password.text,
      allowHttp: _http);

  Future<void> _perform(bool save) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final value = _value;
      value.root;
      if (save) {
        await LibraryConnectionStore.save(value);
      } else {
        final client = WebdavLibrary(value);
        _testing = client;
        try {
          await client.list(client.root);
        } finally {
          client.close();
          _testing = null;
        }
      }
      if (mounted)
        setState(() => _message = save
            ? t('连接和密码已保存在本机，请到首页“远程书库”连接。',
                'Connection and password saved on this device. Open Remote library to connect.')
            : t('连接成功，目录可读取（未写入任何远程文件）。',
                'Connected. Directory is readable; no remote files were written.'));
    } catch (error) {
      if (mounted) setState(() => _message = libraryError(error, zh));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _testing?.close();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(t('远程书库设置', 'Remote library settings'),
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Text(t('连接独立的远程书籍目录，只浏览和下载。不会修改服务器文件，也不会改变现有 WebDAV 同步设置。',
          'Browse and download from a separate remote book directory. Server files and existing sync settings are not modified.')),
      const SizedBox(height: 24),
      TextField(
          controller: _url,
          enabled: !_busy,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
              labelText: t('WebDAV 书库完整地址', 'Full WebDAV library URL'),
              hintText: 'https://example.com/dav/books/',
              border: const OutlineInputBorder())),
      const SizedBox(height: 16),
      TextField(
          controller: _username,
          enabled: !_busy,
          autocorrect: false,
          decoration: InputDecoration(
              labelText:
                  t('用户名（匿名访问可留空）', 'Username (optional for anonymous access)'),
              border: const OutlineInputBorder())),
      const SizedBox(height: 16),
      TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: _hide,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
              labelText: t('密码（保存在本机）', 'Password (saved on this device)'),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                  tooltip: t('显示或隐藏密码', 'Show or hide password'),
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(_hide
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined)))),
      const SizedBox(height: 12),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _http,
          onChanged: _busy ? null : (v) => setState(() => _http = v),
          title: Text(t('允许 HTTP 明文连接', 'Allow unencrypted HTTP')),
          subtitle: Text(t('风险：账号、密码和文件可能被网络中的其他人读取。优先使用 HTTPS 和专用只读账号。',
              'Risk: credentials and files may be intercepted. Prefer HTTPS and a dedicated read-only account.'))),
      Text(t(
          '服务器地址、用户名和密码保存在本机应用配置中，重启后仍保留，本地不额外加密。开启「同步 → 同步 API Key」后，书库配置和密码会跟随自动同步加密上传，各设备需使用相同同步加密密码。导出设置备份时勾选「包含服务配置与 API Key（加密）」即可备份书库配置。清除连接也会同步清除其他已开启此开关设备的书库配置，不删除书籍。',
          'The server, username and password persist locally without additional local encryption. Enable Sync → Sync API keys to include this connection in encrypted automatic sync; devices must use the same encryption password. For backups, select the encrypted service settings option. Clearing this connection also propagates to other opted-in devices; books are kept.')),
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 12, children: [
        OutlinedButton.icon(
            onPressed: _busy ? null : () => _perform(false),
            icon: const Icon(Icons.wifi_tethering),
            label: Text(t('测试连接', 'Test connection'))),
        FilledButton.icon(
            onPressed: _busy ? null : () => _perform(true),
            icon: const Icon(Icons.save_outlined),
            label: Text(t('保存配置', 'Save'))),
        TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                                title: Text(
                                    t('清除书库连接？', 'Clear library connection?')),
                                content: Text(t(
                                    '清除连接配置及密码。开启「同步 API Key」时，下次同步也会清除其他已开启此开关设备的书库配置。不删除本地书籍或服务器文件。',
                                    'Clear the connection and password. If Sync API keys is enabled, the next sync also clears this connection on other opted-in devices. Books and server files are kept.')),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: Text(t('取消', 'Cancel'))),
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: Text(t('清除', 'Clear')))
                                ]));
                    if (confirmed != true || !mounted) return;
                    setState(() => _busy = true);
                    try {
                      await LibraryConnectionStore.clear();
                      await _load();
                      if (mounted) {
                        setState(() => _message = t('已清除连接配置和保存的密码。',
                            'Connection and saved password cleared.'));
                      }
                    } catch (error) {
                      if (mounted) {
                        setState(() => _message = libraryError(error, zh));
                      }
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: Text(t('清除连接', 'Clear connection'))),
      ]),
      if (_busy)
        const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator()),
      if (_message != null)
        Padding(
            padding: const EdgeInsets.only(top: 16), child: Text(_message!)),
      const SizedBox(height: 24),
      const Divider(),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(t('导出时包含密码', 'Include password in export')),
        subtitle: Text(t('默认开启。二维码和 modu: 配置链接将包含未加密的密码，请勿公开分享；不需要携带密码时请关闭。',
            'On by default. The QR image and modu: configuration link contain the unencrypted password. Keep them private; turn this off to omit the password.')),
        value: _exportPassword,
        onChanged:
            _busy ? null : (value) => setState(() => _exportPassword = value),
      ),
      ConfigTransferTile(
        kind: LibraryConfigTransfer.kind,
        label: t('书库 WebDAV 配置', 'Library WebDAV configuration'),
        enabled: !_busy,
        allowReadAny: false,
        importNotice: t(
            '导入仅替换当前表单，不自动保存或连接。请核对地址、账号及 HTTP 风险后点击“保存配置”。不含密码的配置需要重新输入密码，不影响同步 WebDAV 设置。',
            'Import only fills this form; it does not save or connect. Review the address, account and HTTP risk, then press Save. Re-enter the password if omitted. Sync WebDAV settings are not changed.'),
        getData: () => LibraryConfigTransfer.createPayload(_value,
            includePassword: _exportPassword),
        applyData: (data) {
          final value = LibraryConfigTransfer.parse(data);
          if (!mounted) return;
          setState(() {
            _url.text = value.url;
            _username.text = value.username;
            _password.text = value.password;
            _http = value.allowHttp;
            _hide = true;
            _exportPassword = true;
            _message = t('已填入配置，尚未保存。请检查上方连接信息后保存。',
                'Configuration filled in, not saved. Review the connection above and save.');
          });
        },
      ),
    ]);
  }
}
