import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/config/app_identity.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/developer/developer_options_page.dart';
import 'package:anx_reader/page/settings_page/bug_report.dart';
import 'package:anx_reader/page/settings_page/settings_page.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/check_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:anx_reader/utils/app_version.dart';
import 'package:anx_reader/widgets/settings/community_links.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:url_launcher/url_launcher.dart';

class About extends StatelessWidget {
  const About({
    super.key,
    this.leadingColor = false,
    this.onTap,
    this.selected = false,
  });
  final bool leadingColor, selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(L10n.of(context).appAbout),
        leading: Icon(Icons.info_outline,
            color: leadingColor ? Theme.of(context).colorScheme.primary : null),
        trailing: const Icon(Icons.chevron_right),
        selected: selected,
        onTap: onTap ?? () => openAboutPage(context),
      );
}

const int _developerUnlockTapThreshold = 7;
int _developerUnlockTapCount = 0;
Timer? _developerUnlockResetTimer;

void _handleDeveloperUnlockTap(BuildContext context) {
  _developerUnlockTapCount++;
  _developerUnlockResetTimer?.cancel();
  _developerUnlockResetTimer =
      Timer(const Duration(seconds: 2), () => _developerUnlockTapCount = 0);

  final alreadyEnabled = Prefs().developerOptionsEnabled;
  if (_developerUnlockTapCount < _developerUnlockTapThreshold) {
    return;
  }

  _developerUnlockTapCount = 0;
  if (!alreadyEnabled) {
    Prefs().developerOptionsEnabled = true;
    AnxToast.show('Developer options enabled');
  }

  Navigator.of(context).push(MotionCupertinoPageRoute(
    builder: (_) => const DeveloperOptionsPage(),
  ));
}

Future<void> openAboutPage(BuildContext context) =>
    Navigator.of(context).push<void>(
      MotionCupertinoPageRoute(
        builder: (context) => SettingsPageBody(
          title: L10n.of(context).appAbout,
          titleBuilder: (context) => L10n.of(context).appAbout,
          isMobile: true,
          sections: const AboutSettings(),
        ),
      ),
    );

class AboutSettings extends StatefulWidget {
  const AboutSettings({super.key});

  @override
  State<AboutSettings> createState() => _AboutSettingsState();
}

class _AboutSettingsState extends State<AboutSettings> {
  late final Future<String> _version = getAppVersion();

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _version,
        builder: (context, snapshot) {
          final version = snapshot.data ?? '';
          return ListView(
            padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 5),
                child: Center(
                  child: Text(
                    AppIdentity.globalDisplayName,
                    style: TextStyle(
                      fontSize: 50,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const Divider(),
              SettingsSection.content(
                key: const ValueKey('about-app-frame'),
                title: Text(ModuStrings.text(context, '应用信息', 'Application')),
                padding: EdgeInsets.zero,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                    title: Text(L10n.of(context).appVersion),
                    subtitle: Text(version + (kDebugMode ? ' (debug)' : '')),
                    onTap: version.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: version));
                            AnxToast.show(L10n.of(context).notesPageCopied);
                            _handleDeveloperUnlockTap(context);
                          },
                  ),
                  if (EnvVar.enableCheckUpdate)
                    ListTile(
                        leading: const Icon(Icons.system_update_outlined),
                        title: Text(ModuStrings.text(
                            context, '版本检查与更新', 'App updates')),
                        subtitle: Text(ModuStrings.text(
                            context,
                            '检查版本 · 下载 · 安装',
                            'Check version · Download · Install')),
                        onTap: () => checkUpdate(true)),
                  ListTile(
                    key: const ValueKey('about-feedback'),
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(ModuStrings.text(context, '问题反馈与功能建议',
                        'Bug reports and feature requests')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(MotionCupertinoPageRoute(
                          builder: (context) => SettingsPageBody(
                              title: ModuStrings.text(context, '问题反馈与功能建议',
                                  'Bug reports and feature requests'),
                              isMobile: true,
                              sections: const BugReportSettings())));
                    },
                  ),
                ]),
              ),
              SettingsSection.content(
                key: const ValueKey('about-credits-frame'),
                title: Text(
                    ModuStrings.text(context, '开源与许可', 'Credits and licenses')),
                padding: EdgeInsets.zero,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                    title: Text(ModuStrings.text(context, '开源项目与来源',
                        'Open-source projects and credits')),
                    subtitle: Text(ModuStrings.text(
                        context,
                        '默读基于 Anx Reader 与 ReadAny 开发，\n以 GPL-3.0-or-later 发布，非上游官方发行版。',
                        'Modu is based on Anx Reader and ReadAny.\nReleased under GPL-3.0-or-later; not an official upstream release.')),
                    isThreeLine: true,
                    onTap: () => launchUrl(
                      Uri.parse('https://github.com/sobranie2406/modureader'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  ListTile(
                    title: Text(L10n.of(context).appLicense),
                    onTap: () {
                      showLicensePage(
                        context: context,
                        applicationName: AppIdentity.globalDisplayName,
                        applicationVersion: version,
                      );
                    },
                  ),
                ]),
              ),
              const CommunityLinks(),
              const Divider(),
              if (EnvVar.showBeian) ...[
                GestureDetector(
                  onTap: () {
                    launchUrl(Uri.parse('https://beian.miit.gov.cn/'),
                        mode: LaunchMode.externalApplication);
                  },
                  child: const Text('闽ICP备2025091402号-1A'),
                ),
                const Divider(),
              ],
            ],
          );
        },
      );
}
