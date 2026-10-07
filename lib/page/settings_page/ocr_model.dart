import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/ocr/ocr_model_store.dart';
import 'package:anx_reader/service/ocr/ocr_models.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class OcrModelSettings extends StatefulWidget {
  const OcrModelSettings({super.key, this.storeFactory});
  final OcrModelStore Function(OcrModelSpec)? storeFactory;
  @override
  State<OcrModelSettings> createState() => _OcrModelSettingsState();
}

class _OcrModelSettingsState extends State<OcrModelSettings> {
  final Map<String, OcrModelStore> _stores = {};
  final Set<String> _ready = {}, _present = {}, _checking = {};
  final Map<String, String> _errors = {};
  CancelToken? _download;
  String? _downloadingId, _saveError, _deletingId;
  bool _saving = false;
  double _progress = 0;
  bool get _busy =>
      _checking.isNotEmpty ||
      _saving ||
      _download != null ||
      _deletingId != null;
  String t(String zh, String en) => ModuStrings.text(context, zh, en);

  @override
  void initState() {
    super.initState();
    for (final model in OcrModels.all) {
      _stores[model.id] =
          widget.storeFactory?.call(model) ?? OcrModelStore(model: model);
      _checking.add(model.id);
    }
    Prefs().addListener(_preferencesChanged);
    _checkAll();
  }

  void _preferencesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Prefs().removeListener(_preferencesChanged);
    _download?.cancel('OCR settings closed');
    for (final store in _stores.values) {
      store.close();
    }
    super.dispose();
  }

  Future<void> _checkAll() async {
    for (final model in OcrModels.all) {
      if (!mounted) return;
      await _check(model);
    }
  }

  Future<void> _check(OcrModelSpec model) async {
    setState(() {
      _checking.add(model.id);
      _errors.remove(model.id);
    });
    var ready = false, present = false;
    try {
      final store = _stores[model.id]!;
      present = await store.hasLocalFiles();
      if (!mounted) return;
      if (await store.available()) {
        if (!mounted) return;
        await store.verify();
        ready = true;
      }
    } catch (_) {
      if (mounted) {
        _errors[model.id] =
            t('模型校验失败，请重新下载', 'Model verification failed. Download again.');
      }
    }
    if (mounted) {
      setState(() {
        _checking.remove(model.id);
        ready ? _ready.add(model.id) : _ready.remove(model.id);
        present ? _present.add(model.id) : _present.remove(model.id);
      });
    }
  }

  Future<void> _save({String? model, String? source}) async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await Prefs().saveOcrModelSettings(
          model: model ?? Prefs().ocrModelId,
          source: source ?? Prefs().ocrModelDownloadSource);
    } catch (_) {
      if (mounted) _saveError = t('保存失败，请重试', 'Could not save. Please retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startDownload(OcrModelSpec model) async {
    if (_busy) return;
    final token = CancelToken(), store = _stores[model.id]!;
    final previousSelection = Prefs().ocrModelId;
    store.downloadSource = Prefs().ocrModelDownloadSource == 'gitee'
        ? OcrDownloadSource.gitee
        : OcrDownloadSource.upstream;
    setState(() {
      _download = token;
      _downloadingId = model.id;
      _progress = 0;
      _errors.remove(model.id);
      _saveError = null;
    });
    try {
      await store.download(token, (received, total) {
        if (mounted && !token.isCancelled && total > 0) {
          setState(() => _progress = (received / total).clamp(0, 1));
        }
      });
      if (!token.isCancelled && mounted) {
        setState(() {
          _ready.add(model.id);
          _present.add(model.id);
        });
        // Do not overwrite a newer selection imported/synced while downloading.
        if (Prefs().ocrModelId == previousSelection) {
          await _save(model: model.id);
        }
      }
    } catch (_) {
      if (mounted && !token.isCancelled) {
        setState(() => _errors[model.id] = t('下载或校验失败，请重试或切换下载源。已校验的文件会保留。',
            'Download or verification failed. Retry or switch source. Verified files are retained.'));
      }
    } finally {
      if (mounted) {
        try {
          final present = await store.hasLocalFiles();
          if (mounted) {
            setState(() {
              present ? _present.add(model.id) : _present.remove(model.id);
            });
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _download = null;
          _downloadingId = null;
        });
      }
    }
  }

  Future<void> _delete(OcrModelSpec model) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (context) => AlertDialog(
              title: Text(t('删除已下载模型？', 'Delete downloaded model?')),
              content: Text(
                  '${t(model.name, model.englishName)}\n\n${t('仅删除本机该 OCR 模型文件，释放存储空间。书籍、已识别内容和模型选择保持不变；再次使用前需要重新下载。', 'Only this OCR model’s local files will be removed. Books, recognized text and model selection are preserved. Download it again before using it.')}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(t('取消', 'Cancel'))),
                TextButton(
                    key: const ValueKey('ocr-delete-confirm'),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(t('删除', 'Delete'))),
              ],
            ));
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _deletingId = model.id;
      _errors.remove(model.id);
    });
    try {
      await _stores[model.id]!.deleteDownloaded();
      if (mounted) {
        setState(() {
          _ready.remove(model.id);
          _present.remove(model.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('模型已删除，可按需重新下载',
                'Model deleted. You can download it again when needed.'))));
      }
    } catch (_) {
      if (mounted) {
        await _check(
            model); // Refresh after a possible partial filesystem failure.
        if (mounted) {
          setState(() => _errors[model.id] = t('删除失败，模型可能正在使用中。请结束识别或下载后重试。',
              'Could not delete the model. Stop any recognition or download and retry.'));
        }
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => settingsSections(sections: [
        SettingsSection(title: Text(t('OCR 模型', 'OCR model')), tiles: [
          CustomSettingsTile(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t(
                      '用于扫描书籍的文字识别、提取与重排。推荐 PP-OCRv4 中英文版；无需 API Key，下载后可离线使用。',
                      'Recognize, extract and reflow text in scanned books. PP-OCRv4 Chinese / English is recommended. Works offline after download, without an API key.')))),
        ]),
        SettingsSection(
            title: Text(t('本地模型 · 按需下载', 'Local models · On-demand download')),
            tiles: [
              CustomSettingsTile(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(
                            'ocr-source-${Prefs().ocrModelDownloadSource}'),
                        initialValue: Prefs().ocrModelDownloadSource,
                        isExpanded: true,
                        decoration: InputDecoration(
                            labelText: t('模型下载源', 'Model download source')),
                        items: [
                          DropdownMenuItem(
                              value: 'upstream',
                              child:
                                  Text(t('上游（按模型）', 'Upstream (per model)'))),
                          DropdownMenuItem(
                              value: 'gitee',
                              child: Text(t('Gitee 镜像', 'Gitee mirror'))),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) {
                                if (value != null) _save(source: value);
                              },
                      ))),
              CustomSettingsTile(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_saveError != null) ...[
                            Text(_saveError!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                            const SizedBox(height: 12),
                          ],
                          for (final model in OcrModels.all) ...[
                            _modelCard(model),
                            const SizedBox(height: 10)
                          ],
                          Text(
                              t('模型按需下载，不内置在安装包中。只下载所选模型，文件经大小与 SHA-256 校验后使用。切换下载源不会重复下载已校验文件，失败不会自动更换来源。请保持此页打开，离开会取消下载。模型选择和下载源随全局设置备份，模型文件不随备份传输。',
                                  'Models are not bundled. Only the chosen pack is downloaded and verified by size and SHA-256. Switching sources reuses verified files; failures never silently switch sources. Keep this page open; leaving cancels the download. Settings backups include the selection and source, not model files.'),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ))),
            ]),
      ]);

  Widget _modelCard(OcrModelSpec model) {
    final selected = Prefs().ocrModelId == model.id;
    final ready = _ready.contains(model.id),
        checking = _checking.contains(model.id);
    final downloading = _downloadingId == model.id,
        colors = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('ocr-card-${model.id}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: selected ? colors.primaryContainer.withAlpha(90) : null,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant)),
      child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t(model.name, model.englishName),
                  style: Theme.of(context).textTheme.titleMedium),
              if (selected || model.id == OcrModels.defaultModel.id)
                Wrap(spacing: 6, children: [
                  if (model.id == OcrModels.defaultModel.id)
                    Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(t('推荐', 'Recommended'))),
                  if (selected)
                    Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(t('当前', 'Active'))),
                ]),
              const SizedBox(height: 4),
              Text(
                  '${(model.totalBytes / 1048576).toStringAsFixed(1)} MiB · ${t('文字检测与识别', 'Text detection and recognition')}',
                  style: Theme.of(context).textTheme.bodySmall),
              Text(
                  '${t('下载源', 'Download source')}: ${Prefs().ocrModelDownloadSource == 'gitee' ? t('Gitee 镜像', 'Gitee mirror') : model.upstreamName}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                  checking
                      ? t('正在校验模型…', 'Verifying model…')
                      : ready
                          ? t('已下载并校验，可离线识别',
                              'Downloaded and verified. Ready for offline OCR.')
                          : t('未下载或需修复', 'Download required'),
                  style: Theme.of(context).textTheme.bodySmall),
              if (downloading) ...[
                const SizedBox(height: 12),
                EinkStaticIndicator(
                    child: LinearProgressIndicator(
                        value: _progress == 0 ? null : _progress)),
                const SizedBox(height: 4),
                Text(
                    _progress == 0
                        ? t('正在连接下载源…', 'Connecting…')
                        : _progress >= 1
                            ? t('正在校验模型文件…', 'Verifying model files…')
                            : '${(_progress * 100).round()}%',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (_errors[model.id] != null) ...[
                const SizedBox(height: 8),
                Text(_errors[model.id]!, style: TextStyle(color: colors.error)),
              ],
              const SizedBox(height: 10),
              Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (downloading)
                      AnxButton.text(
                          key: ValueKey('ocr-cancel-${model.id}'),
                          onPressed: () => _download?.cancel('User cancelled'),
                          child: Text(t('取消下载', 'Cancel download')))
                    else ...[
                      if (_present.contains(model.id))
                        AnxButton.text(
                            key: ValueKey('ocr-delete-${model.id}'),
                            isLoading: _deletingId == model.id,
                            onPressed: _busy ? null : () => _delete(model),
                            child: Text(t('删除模型', 'Delete model'))),
                      if (ready) ...[
                        AnxButton.text(
                            key: ValueKey('ocr-verify-${model.id}'),
                            onPressed: _busy ? null : () => _check(model),
                            child: Text(t('重新校验', 'Verify again'))),
                        AnxButton.outlined(
                            key: ValueKey('ocr-use-${model.id}'),
                            onPressed: _busy || selected
                                ? null
                                : () => _save(model: model.id),
                            child: Text(selected
                                ? t('使用中', 'Selected')
                                : t('使用', 'Use'))),
                      ] else
                        AnxButton.outlined(
                            key: ValueKey('ocr-download-${model.id}'),
                            onPressed:
                                _busy ? null : () => _startDownload(model),
                            child: Text(t('下载并使用', 'Download and use'))),
                    ],
                  ]),
            ],
          )),
    );
  }
}
