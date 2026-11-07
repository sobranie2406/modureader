import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
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
      if (mounted) {
        setState(() => _message = save
            ? ModuStrings.text(context, "连接已保存，请到“远程书库”打开。",
                "Connection saved. Open Remote library to browse.")
            : ModuStrings.text(context, '连接成功，目录可读取（未写入任何远程文件）。',
                'Connected. Directory is readable; no remote files were written.'));
      }
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
    if (_loading) {
      return const Center(
          child: EinkStaticIndicator(child: CircularProgressIndicator()));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      SettingsSection.content(
        key: const ValueKey('remote-library-settings-frame'),
        title: Text(ModuStrings.text(context, '书库连接', 'Library connection')),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ModuStrings.text(context, "浏览并下载服务器上的书籍。",
                "Browse and download books from your server.")),
            const SizedBox(height: 16),
            TextField(
                controller: _url,
                enabled: !_busy,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                    labelText: ModuStrings.text(
                        context, 'WebDAV 书库完整地址', 'Full WebDAV library URL'),
                    hintText: 'https://example.com/dav/books/',
                    border: const OutlineInputBorder())),
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
                    description: Text(ModuStrings.text(context,
                        "建议使用 HTTPS 连接。", "Use HTTPS for this connection.")))),
            SettingHelp(
                title:
                    Text(ModuStrings.text(context, "同步连接", "Sync connection")),
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
                  onPressed: _busy
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                              animationStyle: AppMotion.style,
                              context: context,
                              builder: (c) => AlertDialog(
                                      title: Text(ModuStrings.text(
                                          context,
                                          '清除书库连接？',
                                          'Clear library connection?')),
                                      content: Text(ModuStrings.text(
                                          context,
                                          "清除连接和密码？开启同步的设备也会更新。",
                                          "Clear the connection and password? This also updates devices with sync enabled.")),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: Text(ModuStrings.text(
                                                context, '取消', 'Cancel'))),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: Text(ModuStrings.text(
                                                context, '清除', 'Clear')))
                                      ]));
                          if (confirmed != true || !mounted) return;
                          setState(() => _busy = true);
                          try {
                            await LibraryConnectionStore.clear();
                            await _load();
                            if (mounted) {
                              setState(() => _message = ModuStrings.text(
                                  context,
                                  '已清除连接配置和保存的密码。',
                                  'Connection and saved password cleared.'));
                            }
                          } catch (error) {
                            if (mounted) {
                              setState(
                                  () => _message = libraryError(error, zh));
                            }
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
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
