import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/knowledge/book_embedding_preferences.dart';
import 'package:modu_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:modu_reader/service/knowledge/local_embedding_models.dart';
import 'package:flutter/material.dart';

Future<void> showBookEmbeddingModelDialog(BuildContext context, Book book) =>
    showDialog<void>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (_) => BookEmbeddingModelDialog(book: book));

class BookEmbeddingModelDialog extends StatefulWidget {
  const BookEmbeddingModelDialog({super.key, required this.book, this.queue});
  final Book book;
  final BookKnowledgeIndexQueue? queue;

  @override
  State<BookEmbeddingModelDialog> createState() =>
      _BookEmbeddingModelDialogState();
}

class _BookEmbeddingModelDialogState extends State<BookEmbeddingModelDialog> {
  late String choice = BookEmbeddingPreferences.choiceFor(widget.book) ?? '';
  bool saving = false;
  String? error;
  BookKnowledgeIndexQueue get queue => widget.queue ?? bookKnowledgeIndexQueue;

  Future<void> save() async {
    if (saving || queue.itemFor(widget.book.id)?.status.isActive == true) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await BookEmbeddingPreferences.save(
          widget.book, choice.isEmpty ? null : choice);
      if (mounted) setState(() => saving = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: queue,
        builder: (context, _) {
          final busy = queue.itemFor(widget.book.id)?.status.isActive == true;
          final prefs = Prefs();
          final defaultName = !prefs.vectorModelEnabled
              ? '向量功能已关闭'
              : prefs.vectorModelMode == 'remote'
                  ? '${prefs.vectorModelConfig['modelId'] ?? '远程模型'}'
                  : LocalEmbeddingModels.byId(prefs.vectorLocalModelId).name;
          Widget option(String value, String title, String subtitle) =>
              RadioListTile<String>(
                value: value,
                title: Text(title),
                subtitle: Text(subtitle),
                enabled: !busy && !saving,
              );
          return AlertDialog(
            title: Text(ModuStrings.text(
                context, '本书向量化模型', 'Embedding model for this book')),
            content: SizedBox(
                width: 440,
                child: RadioGroup<String>(
                    groupValue: choice,
                    onChanged: (value) {
                      if (value != null && !busy && !saving) {
                        setState(() => choice = value);
                        save();
                      }
                    },
                    child: SingleChildScrollView(
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.book.title),
                        option(
                            '',
                            ModuStrings.text(
                                context, '使用默认模型', 'Use default model'),
                            ModuStrings.format(context, '跟随设置中的全局模型：{model}',
                                'Follow the global model: {model}',
                                values: {'model': defaultName})),
                        for (final model in LocalEmbeddingModels.all)
                          option(
                              'local:${model.id}',
                              model.name,
                              ModuStrings.format(
                                  context,
                                  '本地 · {dimensions} 维 · {languages}',
                                  'Local · {dimensions} dimensions · {languages}',
                                  values: {
                                    'dimensions': model.dimensions,
                                    'languages': model.languages
                                  })),
                        option(
                            'remote',
                            ModuStrings.text(
                                context, '使用远程模型', 'Use remote model'),
                            ModuStrings.format(context, '使用向量设置中的接口和密钥：{model}',
                                'Use the endpoint and key from embedding settings: {model}',
                                values: {
                                  'model': prefs.vectorModelConfig['modelId'] ??
                                      ModuStrings.text(
                                          context, '尚未配置', 'Not configured')
                                })),
                        const SizedBox(height: 12),
                        SettingHelp(
                            title: Text(ModuStrings.text(
                                context, "应用模型", "Apply model")),
                            description: Text(ModuStrings.text(
                                context,
                                "保存模型后，在书籍菜单中重新向量化。",
                                "Save the model, then reindex from the book menu."))),
                        if (busy)
                          Text(ModuStrings.text(
                              context,
                              '本书正在排队或向量化，请完成或取消任务后再更换模型。',
                              'This book is queued or being embedded. Finish or cancel the task before changing models.')),
                        if (error != null)
                          Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                      ],
                    )))),
            actions: [
              TextButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: Text(ModuStrings.text(context, '关闭', 'Close'))),
              if (error != null)
                TextButton(
                    onPressed: busy || saving ? null : save,
                    child: Text(ModuStrings.text(context, '重试', 'Retry'))),
            ],
          );
        },
      );
}
