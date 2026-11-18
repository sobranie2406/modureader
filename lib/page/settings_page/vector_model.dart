import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/knowledge/embedding_model_manifest.dart';
import 'package:modu_reader/service/knowledge/local_embedding_models.dart';
import 'package:modu_reader/service/knowledge/onnx_embedding_provider.dart';
import 'package:modu_reader/widgets/bookshelf/stop_vectorization_button.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:modu_reader/widgets/common/anx_button.dart';
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';
import 'package:modu_reader/widgets/settings/settings_title.dart';
import 'package:modu_reader/widgets/settings/offline_model_picker.dart';
import 'package:flutter/material.dart';

class VectorModelSettings extends StatefulWidget {
  const VectorModelSettings({super.key, this.modelStore});

  final LocalEmbeddingModelStore? modelStore;

  @override
  State<VectorModelSettings> createState() => _VectorModelSettingsState();
}

class _VectorModelSettingsState extends State<VectorModelSettings> {
  late final LocalEmbeddingModelStore _localModelStore;
  final Map<String, bool> _downloadedModels = {};
  final Map<String, bool> _bundledModels = {};
  final Map<String, double> _downloadProgress = {};
  final Set<String> _testingModels = {};
  final Set<String> _deletingModels = {};
  bool _loadingLocalModels = true;
  String? _importingId;

  Future<void> _importLocalModel(LocalEmbeddingModel model) async {
    if (_importingId != null ||
        _downloadProgress.isNotEmpty ||
        _testingModels.isNotEmpty ||
        _deletingModels.isNotEmpty) {
      return;
    }
    setState(() => _importingId = model.id);
    try {
      final files = await pickOfflineModelFiles(
          context, model.name, 'model_quantized.onnx\ntokenizer.json');
      if (files == null || !mounted) return;
      await _localModelStore.importFiles(model, files,
          releaseModel: () =>
              LocalOnnxEmbeddingEngine.instance.releaseModel(model.id));
      if (mounted) {
        await _refreshLocalModels();
        if (mounted) {
          AnxToast.show(
              _label('导入并校验完成，可离线使用', 'Imported and verified. Ready offline.'));
        }
      }
    } catch (_) {
      if (mounted) {
        AnxToast.show(_label("导入失败，请选择所选型号的模型和分词器文件。",
            "Import failed. Select the model and tokenizer files for the chosen model."));
      }
    } finally {
      if (mounted) setState(() => _importingId = null);
    }
  }

  @override
  void initState() {
    super.initState();
    Prefs().addListener(_refreshPreferences);
    _localModelStore = widget.modelStore ?? LocalEmbeddingModelStore();
    _localModelStore.downloadSource =
        Prefs().vectorModelDownloadSource == 'gitee'
            ? EmbeddingDownloadSource.gitee
            : EmbeddingDownloadSource.huggingFace;
    if (LocalOnnxEmbeddingProvider.isSupported) _refreshLocalModels();
  }

  @override
  void dispose() {
    Prefs().removeListener(_refreshPreferences);
    _localModelStore.close();
    super.dispose();
  }

  void _refreshPreferences() {
    if (mounted) setState(() {});
  }

  bool get _isChinese => Localizations.localeOf(context).languageCode == 'zh';

  String _label(String zh, String en) => _isChinese ? zh : en;

  Future<void> _refreshLocalModels() async {
    final states = <String, bool>{};
    final bundled = <String, bool>{};
    try {
      for (final model in LocalEmbeddingModels.all) {
        bundled[model.id] = await _localModelStore.isBundled(model);
        states[model.id] =
            bundled[model.id]! || await _localModelStore.isDownloaded(model);
      }
    } catch (_) {
      if (mounted) {
        AnxToast.show(ModuStrings.text(context, '无法读取本地模型，请重新进入设置重试',
            'Could not check local models. Reopen settings to retry.'));
      }
    }
    if (!mounted) return;
    setState(() {
      _downloadedModels
        ..clear()
        ..addAll(states);
      _bundledModels
        ..clear()
        ..addAll(bundled);
      _loadingLocalModels = false;
    });
  }

  Future<void> _downloadLocalModel(LocalEmbeddingModel model) async {
    if (_downloadProgress.isNotEmpty) return;
    setState(() => _downloadProgress[model.id] = 0);
    try {
      await _localModelStore.download(
        model,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress[model.id] = progress);
        },
      );
      if (mounted) {
        Prefs().vectorLocalModelId = model.id;
        setState(() => _downloadedModels[model.id] = true);
        AnxToast.show(_label(
          '${model.name} 下载完成并已设为当前模型',
          '${model.name} downloaded and selected',
        ));
      }
    } catch (error) {
      if (mounted) {
        AnxToast.show(_label('模型下载失败：$error', 'Download failed: $error'));
      }
    } finally {
      if (mounted) setState(() => _downloadProgress.remove(model.id));
    }
  }

  Future<void> _testLocalModel(LocalEmbeddingModel model) async {
    if (_testingModels.contains(model.id) ||
        _deletingModels.contains(model.id)) {
      return;
    }
    setState(() => _testingModels.add(model.id));
    final provider = LocalOnnxEmbeddingProvider(
      model: model,
      store: _localModelStore,
    );
    try {
      final vector = await provider.embed(
        ModuStrings.text(
            context, '默读本地向量模型测试', 'Modu local embedding model test'),
      );
      if (mounted) {
        AnxToast.show(_label(
          '${model.name} 推理成功，${vector.length} 维',
          '${model.name} inference succeeded (${vector.length} dimensions)',
        ));
      }
    } catch (error) {
      if (mounted) {
        AnxToast.show(_label('推理失败：$error', 'Inference failed: $error'));
      }
    } finally {
      try {
        await provider.release();
      } catch (error) {
        if (mounted) {
          AnxToast.show(
              _label('模型释放失败：$error', 'Model cleanup failed: $error'));
        }
      } finally {
        if (mounted) setState(() => _testingModels.remove(model.id));
      }
    }
  }

  Future<void> _deleteLocalModel(LocalEmbeddingModel model) async {
    if (_deletingModels.contains(model.id) ||
        _testingModels.contains(model.id) ||
        _downloadProgress.containsKey(model.id)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      animationStyle: AppMotion.style,
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            ModuStrings.text(context, '删除已下载模型？', 'Delete downloaded model?')),
        content: Text(_label(
          '删除本机的 ${model.name} 模型和分词器？',
          'Delete ${model.name} and its tokenizer from this device?',
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(ModuStrings.text(context, '删除', 'Delete'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingModels.add(model.id));
    try {
      await _localModelStore.deleteDownloaded(model,
          releaseModel: () =>
              LocalOnnxEmbeddingEngine.instance.releaseModel(model.id));
      if (mounted) {
        AnxToast.show(ModuStrings.text(context, '模型已删除，可按需重新下载',
            'Model deleted. You can download it again when needed.'));
      }
    } catch (error) {
      if (mounted) {
        AnxToast.show(_label('删除失败：$error', 'Delete failed: $error'));
      }
    } finally {
      if (mounted) {
        await _refreshLocalModels();
        if (mounted) setState(() => _deletingModels.remove(model.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = Prefs();
    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(ModuStrings.text(context, '向量模型', 'Vector model')),
          tiles: [
            SettingsTile.switchTile(
              initialValue: prefs.vectorModelEnabled,
              onToggle: (value) {
                prefs.vectorModelEnabled = value;
                setState(() {});
              },
              title: Text(
                  ModuStrings.text(context, '启用向量模型', 'Enable vector model')),
              description: Text(ModuStrings.text(context, '用于语义搜索和混合 RAG 检索',
                  'Used by semantic search and hybrid RAG retrieval')),
            ),
            SettingsTile.switchTile(
              initialValue: prefs.autoVectorizeOnImport,
              enabled: prefs.vectorModelEnabled,
              onToggle: (value) {
                prefs.autoVectorizeOnImport = value;
                setState(() {});
              },
              title: Text(ModuStrings.text(
                  context, '导入后自动向量化', 'Vectorize after import')),
              description: Text(ModuStrings.text(context, "导入新书后，自动在后台建立索引。",
                  "Build an index in the background after importing a book.")),
            ),
            CustomSettingsTile(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const StopVectorizationButton(),
                    const SizedBox(height: 8),
                    SettingHelp(
                        title: Text(ModuStrings.text(context, '说明', 'Help')),
                        description: Text(ModuStrings.text(
                            context,
                            "停止全部向量化任务并关闭自动向量化。",
                            "Stop all indexing tasks and turn off automatic indexing."))),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (!LocalOnnxEmbeddingProvider.isSupported)
          SettingsSection(
            title: Text(_label('本地模型', 'Local models')),
            tiles: [
              CustomSettingsTile(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_label(
                    LocalOnnxEmbeddingProvider.unsupportedMessage,
                    LocalOnnxEmbeddingProvider.unsupportedMessageEn,
                  )),
                ),
              ),
            ],
          ),
        if (LocalOnnxEmbeddingProvider.isSupported)
          SettingsSection(
            title: Text(ModuStrings.text(
                context, '本地模型 · 按需下载', 'Local models · On-demand download')),
            tiles: [
              CustomSettingsTile(
                  child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ModuStrings.text(
                        context, '模型下载源', 'Model download source')),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final source in ['huggingFace', 'gitee'])
                        ChoiceChip(
                          key: ValueKey('vector-source-$source'),
                          selected: prefs.vectorModelDownloadSource == source,
                          label: Text(source == 'huggingFace'
                              ? 'Hugging Face'
                              : ModuStrings.text(
                                  context, 'Gitee 镜像', 'Gitee mirror')),
                          onSelected: _downloadProgress.isNotEmpty
                              ? null
                              : (_) {
                                  prefs.vectorModelDownloadSource = source;
                                  _localModelStore.downloadSource =
                                      source == 'gitee'
                                          ? EmbeddingDownloadSource.gitee
                                          : EmbeddingDownloadSource.huggingFace;
                                  setState(() {});
                                },
                        ),
                    ]),
                  ],
                ),
              )),
              CustomSettingsTile(
                child: _buildLocalModels(),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildLocalModels() {
    if (_loadingLocalModels) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
            child: EinkStaticIndicator(child: CircularProgressIndicator())),
      );
    }
    final selectedId = Prefs().vectorLocalModelId;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final model in LocalEmbeddingModels.all) ...[
            _buildLocalModelCard(model, selectedId == model.id),
            if (model != LocalEmbeddingModels.all.last)
              const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SettingHelp(
                title:
                    Text(ModuStrings.text(context, "下载模型", "Download models")),
                description: Text(
                  ModuStrings.text(context, "下载完成前请保持此页打开。切换模型后，请重新向量化书籍。",
                      "Keep this page open until the download finishes. Reindex your books after switching models."),
                  style: Theme.of(context).textTheme.bodySmall,
                )),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalModelCard(LocalEmbeddingModel model, bool selected) {
    final downloaded = _downloadedModels[model.id] ?? false;
    final bundled = _bundledModels[model.id] ?? false;
    final progress = _downloadProgress[model.id];
    final testing = _testingModels.contains(model.id);
    final deleting = _deletingModels.contains(model.id);
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (model.recommended)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      label:
                          Text(ModuStrings.text(context, '推荐', 'Recommended')),
                    ),
                  ),
                if (selected)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(ModuStrings.text(context, '当前', 'Active')),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_modelDescription(model)),
            const SizedBox(height: 8),
            Text(
              '${model.languages} · ${model.sizeLabel} · ${model.dimensions} ${ModuStrings.text(context, '维', 'dimensions')}'
              ' · ${bundled ? ModuStrings.text(context, '已内嵌 · 离线可用', 'Bundled · Offline ready') : downloaded ? ModuStrings.text(context, '已下载', 'Downloaded') : ModuStrings.text(context, '未下载或需修复', 'Download required')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              EinkStaticIndicator(
                  child: LinearProgressIndicator(
                      value: progress == 0 ? null : progress)),
              const SizedBox(height: 4),
              Text(
                progress == 0
                    ? ModuStrings.text(context, '正在连接下载源…', 'Connecting…')
                    : _label(
                        progress >= .99
                            ? '正在校验模型文件…'
                            : '正在下载 ${(progress * 100).round()}%',
                        progress >= .99
                            ? 'Verifying model files…'
                            : 'Downloading ${(progress * 100).round()}%',
                      ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                AnxButton.outlined(
                  key: ValueKey('import-model-${model.id}'),
                  isLoading: _importingId == model.id,
                  onPressed: _importingId != null ||
                          _downloadProgress.isNotEmpty ||
                          _testingModels.isNotEmpty ||
                          _deletingModels.isNotEmpty
                      ? null
                      : () => _importLocalModel(model),
                  child: Text(_label('离线导入', 'Offline import')),
                ),
                if (downloaded) ...[
                  if (!bundled)
                    AnxButton.text(
                      key: ValueKey('delete-model-${model.id}'),
                      isLoading: deleting,
                      onPressed: _importingId != null ||
                              testing ||
                              deleting ||
                              progress != null
                          ? null
                          : () => _deleteLocalModel(model),
                      child: Text(
                          ModuStrings.text(context, '删除模型', 'Delete model')),
                    ),
                  AnxButton.text(
                    isLoading: testing,
                    onPressed: _importingId != null || testing || deleting
                        ? null
                        : () => _testLocalModel(model),
                    child: Text(
                        ModuStrings.text(context, '测试推理', 'Test inference')),
                  ),
                  const SizedBox(width: 8),
                  AnxButton.outlined(
                    onPressed: _importingId != null || selected || deleting
                        ? null
                        : () {
                            Prefs().vectorLocalModelId = model.id;
                            setState(() {});
                            AnxToast.show(_label(
                              '已切换为 ${model.name}，请重新向量化已有书籍',
                              'Switched to ${model.name}; re-vectorize existing books',
                            ));
                          },
                    child: Text(selected
                        ? ModuStrings.text(context, '使用中', 'Selected')
                        : ModuStrings.text(context, '使用', 'Use')),
                  ),
                ] else
                  AnxButton.outlined(
                    isLoading: progress != null,
                    onPressed: _importingId == null &&
                            _downloadProgress.isEmpty &&
                            !deleting
                        ? () => _downloadLocalModel(model)
                        : null,
                    child: Text(
                        ModuStrings.text(context, '下载并使用', 'Download and use')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _modelDescription(LocalEmbeddingModel model) {
    if (!_isChinese) return model.description;
    switch (model.id) {
      case 'all-MiniLM-L6-v2':
        return '轻量、快速的英文句向量模型。';
      case 'bge-small-en-v1.5':
        return '针对英文语义检索优化，匹配效果更强。';
      case 'bge-small-zh-v1.5':
        return '针对中文语义检索优化的轻量向量模型。';
      case 'multilingual-e5-small':
        return '适合中英文及多语言书籍的语义检索。';
    }
    return model.description;
  }
}
