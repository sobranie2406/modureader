import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';

/// 书籍备注/书评编辑页
///
/// - 支持 Markdown 语法，提供「编辑 / 预览」切换
/// - 允许内容为空（清空即删除备注）
/// - 保存成功后通过 [Navigator.pop] 返回最新文本；未保存返回 null
class BookReviewEditorPage extends StatefulWidget {
  const BookReviewEditorPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.initialReview,
  });

  final int bookId;
  final String bookTitle;
  final String initialReview;

  @override
  State<BookReviewEditorPage> createState() => _BookReviewEditorPageState();
}

class _BookReviewEditorPageState extends State<BookReviewEditorPage> {
  late final TextEditingController _controller;
  late String _originalText;
  bool _previewMode = false;
  bool _saving = false;

  bool get _hasChanges => _controller.text != _originalText;

  @override
  void initState() {
    super.initState();
    _originalText = widget.initialReview;
    _controller = TextEditingController(text: widget.initialReview);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _save() async {
    if (_saving) return false;
    setState(() => _saving = true);
    final text = _controller.text;
    try {
      // 允许空内容（清空备注）
      await bookDao.updateReview(widget.bookId, text);
      _originalText = text;
      if (!mounted) return true;
      AnxToast.show(L10n.of(context).bookReviewSaved);
      return true;
    } catch (e) {
      AnxLog.severe('BookReview: save failed: $e');
      if (mounted) {
        AnxToast.show(L10n.of(context).bookReviewSaveFailed);
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _handleSaveAndClose() async {
    // 无改动时直接返回（返回空字符串表示"已保存过、无需更新"）
    if (!_hasChanges) {
      if (mounted) Navigator.pop(context, null);
      return;
    }
    final ok = await _save();
    if (ok && mounted && !_hasChanges) {
      Navigator.pop(context, _originalText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    // 提前捕获 Navigator，避免异步后使用 context（分析器 use_build_context_synchronously）
    final navigator = Navigator.of(context);

    return PopScope(
      canPop: !_saving && !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _saving) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.bookReviewUnsavedTitle),
            content: Text(l10n.bookReviewUnsavedContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.bookReviewDiscard),
              ),
            ],
          ),
        );
        if (leave == true && mounted) {
          navigator.pop(null);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.bookReviewEditorTitle),
          actions: [
            IconButton(
              tooltip: _previewMode
                  ? l10n.bookReviewEditMode
                  : l10n.bookReviewPreviewMode,
              icon: Icon(_previewMode ? Icons.edit_note : Icons.visibility),
              onPressed: _saving
                  ? null
                  : () => setState(() => _previewMode = !_previewMode),
            ),
            IconButton(
              tooltip: l10n.commonSave,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              onPressed: _saving ? null : _handleSaveAndClose,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  widget.bookTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.bookReviewMarkdownHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _previewMode
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _controller.text.trim().isEmpty
                            ? Text(
                                l10n.bookReviewPreviewEmpty,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.outline),
                              )
                            : StyledMarkdown(data: _controller.text),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _controller,
                          readOnly: _saving,
                          maxLines: null,
                          expands: true,
                          autofocus: true,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          style: theme.textTheme.bodyLarge,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: l10n.bookReviewEditorHint,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
