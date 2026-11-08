import 'dart:async';

import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/remote_library/baidu_auth.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class BaiduLibrarySettings extends StatefulWidget {
  const BaiduLibrarySettings({super.key});
  @override
  State<BaiduLibrarySettings> createState() => _BaiduLibrarySettingsState();
}

class _BaiduLibrarySettingsState extends State<BaiduLibrarySettings> {
  final _auth = BaiduAuth();
  CancelToken? _cancel;
  bool _loading = true, _connected = false, _busy = false;
  String? _message;
  String t(String cn, String en) => ModuStrings.text(context, cn, en);

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final connected = await _auth.restore();
      if (mounted) setState(() => _connected = connected);
    } catch (_) {
      if (mounted) {
        setState(() => _message = t(
            '无法读取本机授权，请重试。', 'Cannot read local authorization. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final cancel = CancelToken();
    _cancel = cancel;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final proof = BaiduAuth.newProof();
      final flow = await _auth.start(proof, cancel);
      if (cancel.isCancelled || !mounted) return;
      if (!await launchUrl(flow.url, mode: LaunchMode.externalApplication)) {
        throw const RemoteLibraryException(
            '无法打开百度授权页面。', 'Cannot open Baidu authorization.');
      }
      if (mounted) {
        setState(() => _message = t(
            '请在百度页面完成授权，然后返回默读。', 'Authorize on Baidu, then return to Modu.'));
      }
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (
          mounted && !cancel.isCancelled && DateTime.now().isBefore(deadline)) {
        await Future.any([
          Future<void>.delayed(const Duration(seconds: 5)),
          cancel.whenCancel
        ]);
        if (!mounted || cancel.isCancelled) return;
        if (await _auth.claim(flow.ticket, proof, cancel)) {
          if (mounted) {
            setState(() {
              _connected = true;
              _message = t('已连接，到“远程”切换百度网盘。',
                  'Connected. Select Baidu Netdisk in Remote.');
            });
          }
          return;
        }
      }
      if (mounted && !cancel.isCancelled) {
        setState(() => _message =
            t('授权已超时，请重新连接。', 'Authorization timed out. Please reconnect.'));
      }
    } catch (error) {
      if (mounted && !cancel.isCancelled) {
        setState(() => _message = libraryError(
            error, Localizations.localeOf(context).languageCode == 'zh'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancel = null;
        });
      }
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _auth.disconnect();
      if (mounted) setState(() => _connected = false);
    } catch (error) {
      if (mounted) {
        setState(() => _message = libraryError(
            error, Localizations.localeOf(context).languageCode == 'zh'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _auth.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsSection.content(
        title: Text(t('百度网盘', 'Baidu Netdisk')),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SettingHelp(
              title: Text(_connected
                  ? t('已连接', 'Connected')
                  : t('连接百度网盘', 'Connect Baidu Netdisk')),
              description: Text(t('登录后可浏览网盘，将书籍下载到书架。授权仅保存在本设备。',
                  'Sign in to browse and download books to your bookshelf. Authorization stays on this device.'))),
          const SizedBox(height: 12),
          Wrap(spacing: 12, children: [
            FilledButton.icon(
                onPressed: _loading || _busy ? null : _login,
                icon: const Icon(Icons.cloud_outlined),
                label: Text(_connected
                    ? t('重新授权', 'Authorize again')
                    : t('登录百度网盘', 'Sign in to Baidu'))),
            if (_connected)
              TextButton(
                  onPressed: _busy ? null : _disconnect,
                  child: Text(t('解除连接', 'Disconnect'))),
            if (_cancel != null)
              TextButton(
                  onPressed: () {
                    _cancel?.cancel();
                    setState(() => _message = null);
                  },
                  child: Text(t('取消', 'Cancel'))),
          ]),
          if (_message != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message!)),
        ]),
      );
}
