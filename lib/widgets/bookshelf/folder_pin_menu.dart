import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/providers/bookshelf_pins.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FolderPinMenu extends ConsumerWidget {
  const FolderPinMenu({
    super.key,
    required this.groupId,
    this.menuKey,
    this.onCover = false,
  });

  final int groupId;
  final GlobalKey<PopupMenuButtonState<bool>>? menuKey;
  final bool onCover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final key = folderPinKey(groupId);
    final pinned = ref.watch(bookshelfPinsProvider).contains(key);
    return PopupMenuButton<bool>(
      popUpAnimationStyle: AppMotion.style,
      key: menuKey,
      tooltip: ModuStrings.text(context, '文件夹操作', 'Folder actions'),
      icon: onCover ? null : Icon(pinned ? Icons.push_pin : Icons.more_vert),
      child: onCover
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(150),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(
                  pinned ? Icons.push_pin : Icons.more_vert,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            )
          : null,
      onSelected: (value) async {
        try {
          await ref.read(bookshelfPinsProvider.notifier).setPinned(key, value);
        } catch (_) {
          AnxToast.show(ModuStrings.text(
              context, '置顶设置保存失败，请重试', 'Could not save pin. Please retry.'));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: !pinned,
          child: ListTile(
            leading: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(zh
                ? (pinned ? '取消置顶' : '置顶')
                : (pinned ? 'Unpin' : 'Pin to top')),
          ),
        ),
      ],
    );
  }
}
