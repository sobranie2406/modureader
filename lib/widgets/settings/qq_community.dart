import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared, offline community entry for About and feedback. Keep the supplied
/// invitation image intact: redrawing a stylized QQ code can make it unscannable.
class QqCommunity extends StatelessWidget {
  const QqCommunity({super.key});

  static const groupNumber = '1009765685';
  static const imageAsset = 'assets/images/modu_qq_group.jpg';

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

  void _showCode(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        ModuStrings.text(context, 'QQ 交流群', 'QQ community'),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Image.asset(imageAsset,
                      fit: BoxFit.contain,
                      semanticLabel: ModuStrings.text(
                          context,
                          '默读 QQ 群二维码，群号 $groupNumber',
                          'Modu QQ invitation code, group $groupNumber')),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(ModuStrings.text(context, '可缩放查看二维码，或在 QQ 中搜索群号加入。',
                      'Zoom to view the code, or search for the group number in QQ.')),
                  TextButton.icon(
                    onPressed: () => _copy(context),
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(ModuStrings.text(context, '复制群号 $groupNumber',
                        'Copy group number $groupNumber')),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
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
            Wrap(spacing: 8, children: [
              TextButton.icon(
                onPressed: () => _copy(context),
                icon: const Icon(Icons.copy_outlined),
                label: Text(
                    ModuStrings.text(context, '复制群号', 'Copy group number')),
              ),
              TextButton.icon(
                onPressed: () => _showCode(context),
                icon: const Icon(Icons.qr_code_2),
                label:
                    Text(ModuStrings.text(context, '查看群二维码', 'View QR code')),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
