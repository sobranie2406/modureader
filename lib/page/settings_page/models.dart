import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/page/settings_page/ocr_model.dart';
import 'package:modu_reader/page/settings_page/settings_page.dart';
import 'package:modu_reader/page/settings_page/vector_model.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';
import 'package:modu_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';

class ModelSettings extends StatelessWidget {
  const ModelSettings({super.key});

  @override
  Widget build(BuildContext context) => settingsSections(sections: [
        SettingsSection(
          title: Text(ModuStrings.text(
              context, '离线本地模型设置', 'Offline local model settings')),
          tiles: [
            SettingsTile.navigation(
              key: const ValueKey('model-settings-vector'),
              leading: const Icon(Icons.hub_outlined),
              title: Text(ModuStrings.text(context, '向量模型', 'Vector model')),
              description: Text(ModuStrings.text(context, '语义搜索与 RAG · 本地或远程模型',
                  'Semantic search and RAG · Local or remote models')),
              onPressed: (context) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPageBody(
                    title: ModuStrings.text(context, '向量模型', 'Vector model'),
                    isMobile: true,
                    sections: const VectorModelSettings(),
                  ),
                ),
              ),
            ),
            SettingsTile.navigation(
              key: const ValueKey('model-settings-ocr'),
              leading: const Icon(Icons.document_scanner_outlined),
              title: Text(ModuStrings.text(context, 'OCR 模型', 'OCR model')),
              description: Text(ModuStrings.text(context, '文字识别 · 模型下载与下载源',
                  'Text recognition · Models and download sources')),
              onPressed: (context) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPageBody(
                    title: ModuStrings.text(context, 'OCR 模型', 'OCR model'),
                    isMobile: true,
                    sections: const OcrModelSettings(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ]);
}
