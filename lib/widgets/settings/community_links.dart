import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/widgets/settings/qq_community.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared community entry points in About and Bug reports / Feature requests.
class CommunityLinks extends StatelessWidget {
  const CommunityLinks({super.key});

  static const telegramChannel = 'https://t.me/Modureader';
  static const telegramGroup = 'https://t.me/ModuReaderDiscussion';

  Future<void> _open(BuildContext context, String url) async {
    try {
      if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication))
        return;
    } catch (_) {}
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(ModuStrings.text(context, '无法打开链接，请复制链接后在浏览器中打开。',
          'Could not open the link. Copy it and open it in your browser.')),
    ));
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const QqCommunity(),
          const SizedBox(height: 8),
          Card.outlined(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: const ValueKey('telegram-channel'),
                  leading: const Icon(Icons.campaign_outlined),
                  title: Text(ModuStrings.text(
                      context, 'Telegram 频道', 'Telegram channel')),
                  subtitle: SelectableText('t.me/Modureader',
                      onTap: () => _open(context, telegramChannel)),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _open(context, telegramChannel),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  key: const ValueKey('telegram-group'),
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(ModuStrings.text(
                      context, 'Telegram 讨论群', 'Telegram discussion group')),
                  subtitle: SelectableText('t.me/ModuReaderDiscussion',
                      onTap: () => _open(context, telegramGroup)),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _open(context, telegramGroup),
                ),
              ],
            ),
          ),
        ],
      );
}
