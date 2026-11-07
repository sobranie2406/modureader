import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
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
        animationStyle: AppMotion.style,
        context: context,
        builder: (_) => AppUpdateDialog(
            controller: controller ?? AppUpdateController.instance));

class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog(
      {super.key, required this.controller, this.openBrowser});
  final AppUpdateController controller;
  final Future<bool> Function(Uri)? openBrowser;
  Future<bool> _launchBrowser(Uri url) => openBrowser != null
      ? openBrowser!(url)
      : launchUrl(url, mode: LaunchMode.externalApplication);
  String _text(BuildContext c, String zh, String en) =>
      Localizations.localeOf(c).languageCode == 'zh' ? zh : en;

  Widget _sourcePicker(BuildContext context,
          {required String id,
          required String label,
          required UpdateSource value,
          required ValueChanged<UpdateSource> onChanged}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Wrap(
            key: ValueKey(id),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final source in UpdateSource.values)
                ChoiceChip(
                  key: ValueKey('$id-${source.name}'),
                  selected: value == source,
                  label:
                      Text(source == UpdateSource.github ? 'GitHub' : 'Gitee'),
                  onSelected: controller.busy ? null : (_) => onChanged(source),
                ),
            ],
          ),
        ],
      );

  String _message(BuildContext c, String code) => switch (code) {
        'browser_required' => ModuStrings.text(
            c, "请通过浏览器重新下载 DMG。", "Download the DMG again using your browser."),
        'browser_open_failed' => ModuStrings.text(c, '无法打开默认浏览器，请重试或手动访问官方发布页。',
            'Could not open the default browser. Retry or visit the official release page.'),
        'browser_github_opened' =>
          ModuStrings.text(c, "已在浏览器开始下载。", "Download opened in your browser."),
        'browser_gitee_opened' =>
          ModuStrings.text(c, "已在浏览器开始下载。", "Download opened in your browser."),
        'integrity' => ModuStrings.text(c, '发布信息或安装包校验失败，已阻止安装。请重新检查并下载。',
            'Release or installer verification failed. Installation blocked; check and download again.'),
        'rate_limit' => ModuStrings.text(c, '更新服务器暂时限制请求，请稍后重试。',
            'Update server rate limit reached. Please retry later.'),
        'access_denied' => ModuStrings.text(c, '更新服务器拒绝访问，请检查网络或代理，或从官方发布页下载。',
            'Update server denied access. Check your network or proxy, or download from the official release page.'),
        'not_found' => ModuStrings.text(c, '暂时没有可用的正式发布，请稍后重试。',
            'No stable release is currently available.'),
        'storage' => ModuStrings.text(c, '无法保存安装包，请检查剩余空间和文件权限。',
            'Cannot save the installer. Check free space and file permissions.'),
        'installer' => ModuStrings.text(c, "无法打开安装器，请重新下载官方安装包。",
            "Could not open the installer. Download the official package again."),
        'permission_required' => ModuStrings.text(
            c,
            '请在系统设置允许安装此来源的应用，返回后再次点击安装。',
            'Allow installation from this source in system settings, then return and tap Install again.'),
        'opened' => ModuStrings.text(c, "请按系统提示完成安装。",
            "Follow the system prompts to finish installing."),
        'exported' => ModuStrings.text(c, '已打开 IPA 导出菜单；需自行签名后安装。',
            'IPA export opened. You must sign it yourself before installation.'),
        _ => ModuStrings.text(c, '更新请求失败，请检查网络或代理后重试。',
            'Update request failed. Check your connection or proxy and retry.'),
      };

  String _instructions(BuildContext c) => switch (controller.platform) {
        'android' => ModuStrings.text(c, "下载后按系统提示安装。",
            "Download, then follow the system installation prompts."),
        'macos' => ModuStrings.text(c, "下载 DMG 后退出默读，将新应用拖入“应用程序”替换旧版。",
            "Download the DMG, quit Modu, then drag the new app into Applications to replace it."),
        'windows' => ModuStrings.text(
            c, "退出默读后，运行安装程序。", "Quit Modu, then run the installer."),
        'linux' => ModuStrings.text(c, "打开下载的 DEB 文件，用系统安装器安装。",
            "Open the downloaded DEB with your system installer."),
        'ios' => ModuStrings.text(
            c, "下载 IPA 后，签名安装。", "Download the IPA, then sign and install it."),
        _ => ModuStrings.text(c, '请在发布页查看适合此设备的安装方式。',
            'See the release page for supported installation methods.'),
      };

  Future<void> _openRelease() async {
    final base = controller.source == UpdateSource.gitee
        ? moduMirrorReleasePage
        : moduReleasePage;
    final version = controller.release?.version;
    if (!await _launchBrowser(
        Uri.parse(version == null ? base : '$base/tag/v$version'))) {
      throw PlatformException(code: 'OPEN_FAILED');
    }
  }

  Future<void> _install(BuildContext context) async {
    final yes = await showDialog<bool>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (c) => AlertDialog(
              title: Text(ModuStrings.text(c, '确认更新', 'Confirm update')),
              content: Text(_instructions(c)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text(ModuStrings.text(c, '取消', 'Cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(ModuStrings.text(c, '继续', 'Continue')))
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
          final browserDownload = c.usesBrowserDownload;
          final phase = browserDownload && c.phase == UpdatePhase.ready
              ? UpdatePhase.available
              : c.phase;
          final storeBuild =
              EnvVar.isStoreBuild || EnvVar.isFdroid || EnvVar.isOhosStore;
          final status = switch (phase) {
            UpdatePhase.idle => ModuStrings.text(
                context, "启动时自动检查更新。", "Check for updates on launch."),
            UpdatePhase.checking =>
              ModuStrings.text(context, '正在检查版本…', 'Checking for updates…'),
            UpdatePhase.current => ModuStrings.text(
                context,
                '当前已是最新版本（或高于已发布版本）',
                'Up to date (or newer than the published release)'),
            UpdatePhase.available =>
              ModuStrings.text(context, '发现新版本', 'Update available'),
            UpdatePhase.downloading => _text(
                context,
                '正在下载并校验… ${(c.progress * 100).floor()}%',
                'Downloading and verifying… ${(c.progress * 100).floor()}%'),
            UpdatePhase.ready => ModuStrings.text(
                context, '下载完成，SHA-256 校验通过', 'Downloaded; SHA-256 verified'),
            UpdatePhase.installing => ModuStrings.text(
                context, '正在复核并打开安装包…', 'Verifying and opening installer…'),
            UpdatePhase.openingBrowser => ModuStrings.text(
                context,
                '正在检查下载地址并打开浏览器…',
                'Checking download availability and opening browser…'),
            UpdatePhase.error =>
              ModuStrings.text(context, '更新未完成', 'Update could not complete'),
          };
          return AlertDialog(
            title: SettingHelpTitle(
                title: ModuStrings.text(context, '版本检查与更新', 'App updates'),
                description: storeBuild
                    ? ModuStrings.text(context, '请在原应用商店更新。',
                        'Update through the store you installed from.')
                    : _instructions(context)),
            content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _sourcePicker(context,
                        id: 'update-source',
                        label: ModuStrings.text(context, '更新来源（检查与下载）',
                            'Update source (check and download)'),
                        value: c.source,
                        onChanged: c.selectSource),
                    Text(
                        '${ModuStrings.text(context, '当前版本', 'Installed')}: ${c.currentVersion.isEmpty ? '—' : c.currentVersion}'),
                    if (c.release != null)
                      Text(
                          '${ModuStrings.text(context, '最新正式版', 'Latest stable')}: ${c.release!.version}'),
                    if (c.release != null)
                      Text(
                          '${ModuStrings.text(context, '版本信息来源', 'Release information source')}: ${c.release!.fromMirror ? 'Gitee' : 'GitHub'}'),
                    if (c.checkedAt != null)
                      Text(
                          '${ModuStrings.text(context, '上次检查', 'Last checked')}: ${c.checkedAt!.toLocal().toString().split('.').first}'),
                    const SizedBox(height: 12),
                    Text(status, key: const ValueKey('update-status')),
                    if (c.busy)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: EinkStaticIndicator(
                              child: LinearProgressIndicator(
                                  value: phase == UpdatePhase.downloading
                                      ? c.progress
                                      : null))),
                    if (c.error.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_message(context, c.error),
                              key: const ValueKey('update-error'))),
                    if (c.newer && c.release?.asset == null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(ModuStrings.text(
                              context,
                              "暂无此设备的安装包，请查看发布页。",
                              "No package is available for this device. Check the release page."))),
                    if (c.release?.asset case final asset?)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                              '${asset.name}\n${(asset.size / 1024 / 1024).toStringAsFixed(1)} MiB')),
                    const SizedBox(height: 12),
                    if (!browserDownload && c.downloaded != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SelectableText(c.downloaded!.path,
                              style: Theme.of(context).textTheme.bodySmall)),
                    if (c.release?.notes.isNotEmpty == true)
                      ExpansionTile(
                        title: Text(
                            ModuStrings.text(context, '更新说明', 'Release notes')),
                        children: [SelectableText(c.release!.notes)],
                      ),
                    const SizedBox(height: 8),
                    if (phase == UpdatePhase.downloading)
                      Text(ModuStrings.text(context, "下载将在后台继续。",
                          "The download continues in the background.")),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton(
                          onPressed: c.busy ? null : c.check,
                          child: Text(ModuStrings.text(
                              context, '检查更新', 'Check for updates'))),
                      TextButton(
                          onPressed: () async {
                            try {
                              await _openRelease();
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.maybeOf(context)
                                    ?.showSnackBar(SnackBar(
                                        content: Text(ModuStrings.text(
                                            context,
                                            '无法打开浏览器，请稍后重试。',
                                            'Could not open the browser. Please retry.'))));
                              }
                            }
                          },
                          child: Text(ModuStrings.text(
                              context, '发布页面', 'Release page'))),
                      if (phase == UpdatePhase.downloading)
                        TextButton(
                            onPressed: c.cancelDownload,
                            child: Text(ModuStrings.text(
                                context, '取消下载', 'Cancel download'))),
                      if (!storeBuild &&
                          c.newer &&
                          c.release?.asset != null &&
                          browserDownload) ...[
                        FilledButton(
                            onPressed: c.busy
                                ? null
                                : () => c.openBrowserDownload(_launchBrowser),
                            child: Text(ModuStrings.text(
                                context, '浏览器下载更新', 'Download in browser'))),
                      ],
                      if (!storeBuild &&
                          !browserDownload &&
                          c.newer &&
                          c.release?.asset != null &&
                          c.downloaded == null)
                        FilledButton(
                            onPressed: c.busy ? null : c.download,
                            child: Text(ModuStrings.text(
                                context, '下载更新', 'Download update'))),
                      if (!storeBuild &&
                          !browserDownload &&
                          c.newer &&
                          c.downloaded != null)
                        FilledButton(
                            onPressed: c.busy ? null : () => _install(context),
                            child: Text(c.platform == 'ios'
                                ? ModuStrings.text(
                                    context, '导出 IPA', 'Export IPA')
                                : ModuStrings.text(
                                    context, '安装更新', 'Install update'))),
                    ]),
                  ],
                ))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(ModuStrings.text(context, '关闭', 'Close')))
            ],
          );
        },
      );
}
