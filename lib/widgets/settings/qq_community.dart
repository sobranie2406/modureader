import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared, copyable group number for About and feedback.
class QqCommunity extends StatelessWidget {
  const QqCommunity({super.key});

  static const groupNumber = '1009765685';

  Future<void> _copy(BuildContext context) async {
    try {
      await Clipboard.setData(const ClipboardData(text: groupNumber));
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content:
            Text(ModuStrings.text(context, '群号已复制', 'Group number copied')),
      ));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(ModuStrings.text(context, '复制失败，请手动复制群号',
            'Could not copy. Please copy the group number manually.')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                ModuStrings.text(context, 'Modu 默读交流反馈 · QQ 群',
                    'Modu community & feedback · QQ'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            const SelectableText(groupNumber),
            const SizedBox(height: 4),
            Text(ModuStrings.text(context, '在 QQ 搜索群号申请加入。',
                'Search for the group number in QQ to request to join.')),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                onPressed: () => _copy(context),
                icon: const Icon(Icons.copy_outlined),
                label: Text(
                    ModuStrings.text(context, '复制群号', 'Copy group number')),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
