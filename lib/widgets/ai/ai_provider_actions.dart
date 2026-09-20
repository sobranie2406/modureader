import 'package:anx_reader/models/ai_provider.dart';
import 'package:flutter/material.dart';

Future<bool> confirmDeleteAiProvider(
    BuildContext context, AiProvider provider) async {
  if (provider.isBuiltin) return false;
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(zh ? '删除供应商？' : 'Delete provider?'),
                content: Text(zh
                    ? '删除“${provider.title}”及其已保存的模型配置和 API Key？如果正在使用此供应商，后续调用将改用其他已启用的供应商。不会删除对话、笔记或书籍。'
                    : 'Delete “${provider.title}”, its model configuration and saved API keys? Future calls will fall back to another enabled provider if needed. Chats, notes and books are not deleted.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(zh ? '取消' : 'Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(zh ? '删除' : 'Delete'))
                ],
              )) ??
      false;
}
