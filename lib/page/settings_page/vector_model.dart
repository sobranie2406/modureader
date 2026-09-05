import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/knowledge/embedding_provider.dart';
import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:anx_reader/service/knowledge/onnx_embedding_provider.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';

class VectorModelSettings extends StatefulWidget {
  const VectorModelSettings({super.key});

  @override
  State<VectorModelSettings> createState() => _VectorModelSettingsState();
}

class _VectorModelSettingsState extends State<VectorModelSettings> {
  late final TextEditingController _nameController;
  late final TextEditingController _modelController;
  late final TextEditingController _endpointController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _dimensionController;
  late final LocalEmbeddingModelStore _localModelStore;
  final Map<String, bool> _downloadedModels = {};
  final Map<String, double> _downloadProgress = {};
  final Set<String> _testingModels = {};
  bool _loadingLocalModels = true;
  bool _obscureApiKey = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final config = VectorModelConfig.fromJson(Prefs().vectorModelConfig);
    _nameController = TextEditingController(text: config.name);
    _modelController = TextEditingController(text: config.modelId);
    _endpointController = TextEditingController(text: config.endpoint);
    _apiKeyController = TextEditingController(text: config.apiKey);
    _descriptionController = TextEditingController(text: config.description);
    _dimensionController = TextEditingController(
      text: config.dimension?.toString() ?? '',
    );
    _localModelStore = LocalEmbeddingModelStore();
    _refreshLocalModels();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _modelController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    _descriptionController.dispose();
    _dimensionController.dispose();
    _localModelStore.close();
    super.dispose();
  }

  bool get _isChinese => Localizations.localeOf(context).languageCode == 'zh';

  String _label(String zh, String en) => _isChinese ? zh : en;

  VectorModelConfig _formConfig({int? detectedDimension}) {
    return VectorModelConfig(
      name: _nameController.text.trim(),
      modelId: _modelController.text.trim(),
      endpoint: _endpointController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      description: _descriptionController.text.trim(),
      dimension:
          detectedDimension ?? int.tryParse(_dimensionController.text.trim()),
    );
  }

  Future<void> _save({int? detectedDimension}) async {
    final config = _formConfig(detectedDimension: detectedDimension);
    await Prefs().saveVectorModelConfig(config.toJson());
    if (detectedDimension != null) {
      _dimensionController.text = detectedDimension.toString();
    }
    if (mounted) {
      AnxToast.show(_label('向量模型配置已保存', 'Vector model saved'));
      setState(() {});
    }
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() => _testing = true);
    OpenAiCompatibleEmbeddingProvider? provider;
    try {
      provider = OpenAiCompatibleEmbeddingProvider(config: _formConfig());
      final vector = await provider
          .embed(_label('默读向量模型连接测试', 'Modu embedding connection test'));
      await _save(detectedDimension: vector.length);
      if (mounted) {
        AnxToast.show(
          _label(
            '连接成功，向量维度 ${vector.length}',
            'Connected, ${vector.length} dimensions',
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        AnxToast.show(_label('连接失败：$error', 'Connection failed: $error'));
      }
    } finally {
      provider?.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _refreshLocalModels() async {
    final states = <String, bool>{};
    for (final model in LocalEmbeddingModels.all) {
      states[model.id] = await _localModelStore.isDownloaded(model);
    }
    if (!mounted) return;
    setState(() {
      _downloadedModels
        ..clear()
        ..addAll(states);
      _loadingLocalModels = false;
    });
  }

  Future<void> _downloadLocalModel(LocalEmbeddingModel model) async {
    if (_downloadProgress.containsKey(model.id)) return;
    setState(() => _downloadProgress[model.id] = 0);
    try {
      await _localModelStore.download(
        model,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress[model.id] = progress);
        },
      );
      Prefs().vectorLocalModelId = model.id;
      if (mounted) {
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
    if (_testingModels.contains(model.id)) return;
    setState(() => _testingModels.add(model.id));
    try {
      final provider = LocalOnnxEmbeddingProvider(
        model: model,
        store: _localModelStore,
      );
      final vector = await provider.embed(
        model.id == 'bge-small-zh-v1.5'
            ? '默读本地向量模型测试'
            : 'Modu local embedding model test',
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
      if (mounted) setState(() => _testingModels.remove(model.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = Prefs();
    final isRemote = prefs.vectorModelMode == 'remote';
    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(_label('向量模型', 'Vector model')),
          tiles: [
            SettingsTile.switchTile(
              initialValue: prefs.vectorModelEnabled,
              onToggle: (value) {
                prefs.vectorModelEnabled = value;
                setState(() {});
              },
              title: Text(_label('启用向量模型', 'Enable vector model')),
              description: Text(_label(
                '用于语义搜索和混合 RAG 检索',
                'Used by semantic search and hybrid RAG retrieval',
              )),
            ),
            SettingsTile.switchTile(
              initialValue: prefs.autoVectorizeOnImport,
              enabled: prefs.vectorModelEnabled,
              onToggle: (value) {
                prefs.autoVectorizeOnImport = value;
                setState(() {});
              },
              title: Text(_label(
                '导入后自动向量化',
                'Vectorize after import',
              )),
              description: Text(_label(
                '新导入书籍会在后台排队建立索引；默认关闭，避免意外消耗模型额度。',
                'New books are indexed in the background. Disabled by default to avoid unexpected API usage.',
              )),
            ),
          ],
        ),
        SettingsSection(
          title: Text(_label('模型来源', 'Model source')),
          tiles: [
            CustomSettingsTile(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AnxSegmentedButton<String>(
                  selected: {prefs.vectorModelMode},
                  segments: [
                    SegmentButtonItem(
                      value: 'builtin',
                      label: _label('内置本地模型', 'Built-in local'),
                      icon: const Icon(Icons.computer_rounded),
                    ),
                    SegmentButtonItem(
                      value: 'remote',
                      label: _label('远程 API', 'Remote API'),
                      icon: const Icon(Icons.cloud_outlined),
                    ),
                  ],
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    prefs.vectorModelMode = selection.first;
                    setState(() {});
                  },
                ),
              ),
            ),
          ],
        ),
        if (!isRemote)
          SettingsSection(
            title: Text(_label('内置模型', 'Built-in model')),
            tiles: [
              CustomSettingsTile(
                child: _buildLocalModels(),
              ),
            ],
          ),
        if (isRemote)
          SettingsSection(
            title: Text(_label('远程模型', 'Remote model')),
            tiles: [
              CustomSettingsTile(child: _buildRemoteForm()),
            ],
          ),
      ],
    );
  }

  Widget _buildLocalModels() {
    if (_loadingLocalModels) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final selectedId = Prefs().vectorLocalModelId;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (final model in LocalEmbeddingModels.all) ...[
            _buildLocalModelCard(model, selectedId == model.id),
            if (model != LocalEmbeddingModels.all.last)
              const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _label(
                '模型下载后完全在本机执行。切换模型后，请对已有书籍重新向量化。',
                'Downloaded models run entirely on-device. Re-vectorize existing books after switching models.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalModelCard(LocalEmbeddingModel model, bool selected) {
    final downloaded = _downloadedModels[model.id] ?? false;
    final progress = _downloadProgress[model.id];
    final testing = _testingModels.contains(model.id);
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: selected ? colors.primaryContainer.withAlpha(90) : null,
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
                      label: Text(_label('推荐', 'Recommended')),
                    ),
                  ),
                if (selected)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_label('当前', 'Active')),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_modelDescription(model)),
            const SizedBox(height: 8),
            Text(
              '${model.languages} · ${model.sizeLabel} · ${model.dimensions} ${_label('维', 'dimensions')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress == 0 ? null : progress),
              const SizedBox(height: 4),
              Text(
                progress == 0
                    ? _label('正在连接下载源…', 'Connecting…')
                    : _label(
                        '正在下载 ${(progress * 100).round()}%',
                        'Downloading ${(progress * 100).round()}%',
                      ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (downloaded) ...[
                  AnxButton.text(
                    isLoading: testing,
                    onPressed: testing ? null : () => _testLocalModel(model),
                    child: Text(_label('测试推理', 'Test inference')),
                  ),
                  const SizedBox(width: 8),
                  AnxButton.outlined(
                    onPressed: selected
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
                        ? _label('使用中', 'Selected')
                        : _label('使用', 'Use')),
                  ),
                ] else
                  AnxButton.outlined(
                    isLoading: progress != null,
                    onPressed: progress == null
                        ? () => _downloadLocalModel(model)
                        : null,
                    child: Text(_label('下载模型', 'Download model')),
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

  Widget _buildRemoteForm() {
    InputDecoration decoration(String label, {String? helper}) {
      return InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _nameController,
            decoration: decoration(_label('名称', 'Name')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            decoration: decoration(_label('模型 ID', 'Model ID')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _endpointController,
            keyboardType: TextInputType.url,
            decoration: decoration(
              _label('API 端点', 'API endpoint'),
              helper: _label(
                '支持 API 根地址、/v1 地址或完整 /embeddings 地址',
                'Accepts an API root, /v1 base, or full /embeddings URL',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            decoration: decoration(_label('API 密钥', 'API key')).copyWith(
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscureApiKey = !_obscureApiKey),
                icon: Icon(
                  _obscureApiKey ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dimensionController,
            keyboardType: TextInputType.number,
            decoration: decoration(_label(
              '维度（可留空，测试后自动填写）',
              'Dimensions (optional; detected by test)',
            )),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            decoration: decoration(_label('描述（可选）', 'Description')),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AnxButton.outlined(
                isLoading: _testing,
                onPressed: _testing ? null : _testConnection,
                child: Text(_label('测试', 'Test')),
              ),
              const SizedBox(width: 8),
              AnxButton(
                onPressed: () => _save(),
                child: Text(_label('保存', 'Save')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
