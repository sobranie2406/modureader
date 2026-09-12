import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/knowledge/book_embedding_preferences.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:flutter/material.dart';

Future<void> showBookEmbeddingModelDialog(BuildContext context, Book book) =>
    showDialog<void>(
        context: context, builder: (_) => BookEmbeddingModelDialog(book: book));

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
    if (saving || queue.itemFor(widget.book.id)?.status.isActive == true)
      return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await BookEmbeddingPreferences.save(
          widget.book, choice.isEmpty ? null : choice);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted)
        setState(() {
          saving = false;
          error = '保存失败，请重试';
        });
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
                groupValue: choice,
                title: Text(title),
                subtitle: Text(subtitle),
                onChanged: busy || saving
                    ? null
                    : (value) => setState(() => choice = value!),
              );
          return AlertDialog(
            title: const Text('本书向量化模型'),
            content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.book.title),
                    option('', '使用默认模型', '跟随设置中的全局模型：$defaultName'),
                    for (final model in LocalEmbeddingModels.all)
                      option('local:${model.id}', model.name,
                          '本地 · ${model.dimensions} 维 · ${model.languages}'),
                    option('remote', '使用远程模型',
                        '使用向量设置中的接口和密钥：${prefs.vectorModelConfig['modelId'] ?? '尚未配置'}'),
                    const SizedBox(height: 12),
                    const Text(
                        '仅影响本书，不修改全局设置。保存不会自动开始任务；已有索引需在书籍菜单中重新向量化。模型不匹配期间，AI 检索仅使用关键词，避免混用向量。'),
                    const Text(
                        '远程模型会发送书籍片段到配置的服务商。本书选择不另存 API 密钥；全局向量功能关闭时，本书也不进行向量推理。'),
                    if (busy) const Text('本书正在排队或向量化，请完成或取消任务后再更换模型。'),
                    if (error != null)
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ],
                ))),
            actions: [
              TextButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: busy || saving ? null : save,
                  child: const Text('保存')),
            ],
          );
        },
      );
}
