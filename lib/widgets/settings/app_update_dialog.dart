import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:anx_reader/service/update/app_update.dart';
import 'package:anx_reader/utils/env_var.dart';

Future<void> showAppUpdateDialog(BuildContext context,
        {AppUpdateController? controller}) =>
    showDialog<void>(
        context: context,
        builder: (_) => AppUpdateDialog(
            controller: controller ?? AppUpdateController.instance));

class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({super.key, required this.controller});
  final AppUpdateController controller;
  String _text(BuildContext c, String zh, String en) =>
      Localizations.localeOf(c).languageCode == 'zh' ? zh : en;

  String _message(BuildContext c, String code) => switch (code) {
        'integrity' => _text(c, '发布信息或安装包校验失败，已阻止安装。请重新检查并下载。',
            'Release or installer verification failed. Installation blocked; check and download again.'),
        'rate_limit' => _text(c, '更新服务器暂时限制请求，请稍后重试。',
            'Update server rate limit reached. Please retry later.'),
        'access_denied' => _text(c, '更新服务器拒绝访问，请检查网络或代理，或从官方发布页下载。',
            'Update server denied access. Check your network or proxy, or download from the official release page.'),
        'not_found' => _text(c, '暂时没有可用的正式发布，请稍后重试。',
            'No stable release is currently available.'),
        'storage' => _text(c, '无法保存安装包，请检查剩余空间和文件权限。',
            'Cannot save the installer. Check free space and file permissions.'),
        'installer' => _text(c, '无法打开安装器，或 Android 包名、签名、版本不匹配。请使用官方安装包。',
            'Installer could not open, or Android package/signature/version does not match. Use an official package.'),
        'permission_required' => _text(c, '请在系统设置允许安装此来源的应用，返回后再次点击安装。',
            'Allow installation from this source in system settings, then return and tap Install again.'),
        'opened' => _text(c, '已打开系统安装界面，请按提示操作；这不表示安装已完成。',
            'The system installer was opened. Follow its instructions; installation is not yet confirmed.'),
        'exported' => _text(c, '已打开 IPA 导出菜单；需自行签名后安装。',
            'IPA export opened. You must sign it yourself before installation.'),
        _ => _text(c, '更新请求失败，请检查网络或代理后重试。',
            'Update request failed. Check your connection or proxy and retry.'),
      };

  String _instructions(BuildContext c) => switch (controller.platform) {
        'android' => _text(c, '安装需要系统确认；首次使用可能需要允许安装此来源的应用。不会卸载旧版或删除书库。',
            'Installation requires system confirmation and possibly permission for this source. Your existing app and library will not be uninstalled.'),
        'macos' => _text(c, '打开 DMG 后，退出默读，再将新应用拖入“应用程序”替换旧版。当前发行包未经 Apple 公证。',
            'Open the DMG, quit Modu, and drag the new app into Applications to replace it. Current packages are not Apple-notarized.'),
        'windows' => _text(c, '打开安装程序后按系统提示覆盖安装；如提示应用正在运行，请先完成同步并退出默读。',
            'Follow the installer to update. If prompted, finish syncing and quit Modu first.'),
        'linux' => _text(
            c,
            'DEB 面向 Debian 13，由系统软件安装器完成更新；未配置安装器时请自行安装已下载的 DEB。',
            'DEB packages target Debian 13. Use your system package installer, or install the downloaded DEB manually.'),
        'ios' => _text(c, '此发行渠道提供未签名 IPA，iOS 不允许在应用内直接安装。可下载并导出，再自行签名安装。',
            'This channel provides unsigned IPA files. iOS cannot install them directly in-app. Download/export and sign them yourself.'),
        _ => _text(c, '请在发布页查看适合此设备的安装方式。',
            'See the release page for supported installation methods.'),
      };

  Future<void> _openRelease() async {
    if (!await launchUrl(Uri.parse(controller.release?.url ?? moduReleasePage),
        mode: LaunchMode.externalApplication)) {
      throw PlatformException(code: 'OPEN_FAILED');
    }
  }

  Future<void> _install(BuildContext context) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text(_text(c, '确认更新', 'Confirm update')),
              content: Text(_instructions(c)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text(_text(c, '取消', 'Cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(_text(c, '继续', 'Continue')))
              ],
            ));
    if (yes != true || !context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    await controller.install((file) async {
      switch (controller.platform) {
        case 'android':
          return await const MethodChannel('com.modu.reader/app_update')
              .invokeMethod<String>('install', {'path': file.path});
        case 'windows':
          await Process.start(file.path, [], mode: ProcessStartMode.detached);
        case 'macos':
          if (!await launchUrl(Uri.file(file.path),
              mode: LaunchMode.externalApplication)) {
            throw PlatformException(code: 'OPEN_FAILED');
          }
        case 'linux':
          final result = await Process.run('xdg-open', [file.path]);
          if (result.exitCode != 0) {
            throw PlatformException(code: 'OPEN_FAILED');
          }
        case 'ios':
          await SharePlus.instance.share(ShareParams(
              files: [XFile(file.path)], sharePositionOrigin: shareOrigin));
          return 'exported';
        default:
          throw PlatformException(code: 'UNSUPPORTED');
      }
      return 'opened';
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final c = controller;
          final phase = c.phase;
          final storeBuild =
              EnvVar.isStoreBuild || EnvVar.isFdroid || EnvVar.isOhosStore;
          final status = switch (phase) {
            UpdatePhase.idle => _text(context, '每次启动自动检查正式版本，不会自动下载或安装。',
                'Checks for stable releases on each launch. Downloads and installation require your action.'),
            UpdatePhase.checking =>
              _text(context, '正在检查版本…', 'Checking for updates…'),
            UpdatePhase.current => _text(context, '当前已是最新版本（或高于已发布版本）',
                'Up to date (or newer than the published release)'),
            UpdatePhase.available =>
              _text(context, '发现新版本', 'Update available'),
            UpdatePhase.downloading => _text(
                context,
                '正在下载并校验… ${(c.progress * 100).floor()}%',
                'Downloading and verifying… ${(c.progress * 100).floor()}%'),
            UpdatePhase.ready => _text(
                context, '下载完成，SHA-256 校验通过', 'Downloaded; SHA-256 verified'),
            UpdatePhase.installing =>
              _text(context, '正在复核并打开安装包…', 'Verifying and opening installer…'),
            UpdatePhase.error =>
              _text(context, '更新未完成', 'Update could not complete'),
          };
          return AlertDialog(
            title: Text(_text(context, '版本检查与更新', 'App updates')),
            content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        '${_text(context, '当前版本', 'Installed')}: ${c.currentVersion.isEmpty ? '—' : c.currentVersion}'),
                    if (c.release != null)
                      Text(
                          '${_text(context, '最新正式版', 'Latest stable')}: ${c.release!.version}'),
                    if (c.release != null)
                      Text(
                          '${_text(context, '版本信息来源', 'Release information source')}: ${c.release!.fromMirror ? 'Gitee' : 'GitHub'}'),
                    if (c.checkedAt != null)
                      Text(
                          '${_text(context, '上次检查', 'Last checked')}: ${c.checkedAt!.toLocal().toString().split('.').first}'),
                    const SizedBox(height: 12),
                    Text(status, key: const ValueKey('update-status')),
                    if (c.busy)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(
                              value: phase == UpdatePhase.downloading
                                  ? c.progress
                                  : null)),
                    if (c.error.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_message(context, c.error),
                              key: const ValueKey('update-error'))),
                    if (c.newer && c.release?.asset == null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_text(
                              context,
                              '尚无匹配当前架构且带有效校验信息的安装包，请查看发布页。',
                              'No matching package with valid verification metadata. See the release page.'))),
                    if (c.release?.asset case final asset?)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                              '${asset.name}\n${(asset.size / 1024 / 1024).toStringAsFixed(1)} MiB')),
                    const SizedBox(height: 12),
                    Text(storeBuild
                        ? _text(context, '商店版本请通过原应用商店更新，不进行侧载安装。',
                            'Update store builds through their original store, not sideloading.')
                        : _instructions(context)),
                    if (c.downloaded != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SelectableText(c.downloaded!.path,
                              style: Theme.of(context).textTheme.bodySmall)),
                    if (c.release?.notes.isNotEmpty == true)
                      ExpansionTile(
                        title: Text(_text(context, '更新说明', 'Release notes')),
                        children: [SelectableText(c.release!.notes)],
                      ),
                    const SizedBox(height: 8),
                    Text(
                        _text(
                            context,
                            '优先通过 GitHub 检查更新和下载安装包，仅在连接失败、超时或服务不可用时改用 Gitee。下载后必须通过文件大小与 SHA-256 校验。不发送书籍、笔记或账号密钥。',
                            'Checks GitHub first and downloads from GitHub first; uses Gitee only if the connection fails, times out or the service is unavailable. File size and SHA-256 verification are required. No books, notes or account keys are sent.'),
                        style: Theme.of(context).textTheme.bodySmall),
                    if (phase == UpdatePhase.downloading)
                      Text(_text(context, '关闭此窗口后下载继续，可从“关于默读”返回查看或取消。',
                          'Closing this dialog keeps downloading. Return from About to view progress or cancel.')),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton(
                          onPressed: c.busy ? null : c.check,
                          child: Text(
                              _text(context, '检查更新', 'Check for updates'))),
                      TextButton(
                          onPressed: () async {
                            try {
                              await _openRelease();
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.maybeOf(context)
                                    ?.showSnackBar(SnackBar(
                                        content: Text(_text(
                                            context,
                                            '无法打开浏览器，请稍后重试。',
                                            'Could not open the browser. Please retry.'))));
                              }
                            }
                          },
                          child: Text(_text(context, '发布页面', 'Release page'))),
                      if (phase == UpdatePhase.downloading)
                        TextButton(
                            onPressed: c.cancelDownload,
                            child: Text(
                                _text(context, '取消下载', 'Cancel download'))),
                      if (!storeBuild &&
                          c.newer &&
                          c.release?.asset != null &&
                          c.downloaded == null)
                        FilledButton(
                            onPressed: c.busy ? null : c.download,
                            child: Text(
                                _text(context, '下载更新', 'Download update'))),
                      if (!storeBuild && c.newer && c.downloaded != null)
                        FilledButton(
                            onPressed: c.busy ? null : () => _install(context),
                            child: Text(c.platform == 'ios'
                                ? _text(context, '导出 IPA', 'Export IPA')
                                : _text(context, '安装更新', 'Install update'))),
                    ]),
                  ],
                ))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(_text(context, '关闭', 'Close')))
            ],
          );
        },
      );
}
