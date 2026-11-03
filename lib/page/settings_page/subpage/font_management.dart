import 'package:anx_reader/widgets/settings/font_name_preview.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/font_list.dart';
import 'package:anx_reader/service/font.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fonts.dart';
import 'installed_fonts.dart';

class FontManagementPage extends ConsumerWidget {
  const FontManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
          title: Text(ModuStrings.text(context, '字体管理', 'Font management'))),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(children: [
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(L10n.of(context).downloadFonts),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FontsSettingPage())),
              ),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: Text(ModuStrings.text(context, '导入字体', 'Import fonts')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final folder = await showModalBottomSheet<bool>(
                    context: context,
                    builder: (context) => SafeArea(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                          leading: const Icon(Icons.file_upload_outlined),
                          title: Text(ModuStrings.text(context, '选择字体文件（可多选）',
                              'Select font files (multiple allowed)')),
                          onTap: () => Navigator.pop(context, false)),
                      ListTile(
                          leading: const Icon(Icons.folder_open),
                          title: Text(ModuStrings.text(
                              context, '导入整个文件夹', 'Import a folder')),
                          onTap: () => Navigator.pop(context, true)),
                    ])),
                  );
                  if (folder == null || !context.mounted) return;
                  try {
                    await importFont(
                        folder: folder,
                        onApplied: (font) {
                          final reader = epubPlayerKey.currentState;
                          if (reader != null && reader.mounted) {
                            reader.changeFont(font);
                          }
                        });
                    if (context.mounted) {
                      ref.invalidate(fontListProvider);
                      ref.invalidate(fontPreviewProvider);
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ModuStrings.text(context, '字体导入失败，请重试。',
                              'Could not import fonts. Please try again.'))));
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.font_download_outlined),
                title: Text(ModuStrings.text(
                    context, '管理已安装字体', 'Manage installed fonts')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const InstalledFontsPage())),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
