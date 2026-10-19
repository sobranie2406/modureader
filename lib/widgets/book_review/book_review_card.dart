import 'dart:async';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/book_review_editor_page.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/sync_database_revision.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 书籍详情页的「备注/书评」卡片
///
/// - 内容支持 Markdown 渲染（复用 StyledMarkdown）
/// - 允许为空（未填写时显示引导提示）
/// - 点击卡片进入编辑页；保存后刷新书架
///
/// 书评独立同步，避免与书籍信息、阅读进度互相覆盖。
class BookReviewCard extends ConsumerStatefulWidget {
  const BookReviewCard({
    super.key,
    required this.bookId,
    required this.bookTitle,
  });

  final int bookId;
  final String bookTitle;

  @override
  ConsumerState<BookReviewCard> createState() => _BookReviewCardState();
}

class _BookReviewCardState extends ConsumerState<BookReviewCard> {
  String _review = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BookReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId) {
      _loading = true;
      _load();
    }
  }

  Future<String?> _load() async {
    final bookId = widget.bookId;
    try {
      final text = await bookDao.selectReview(bookId);
      if (!mounted || bookId != widget.bookId) return null;
      setState(() {
        _review = text;
        _loading = false;
      });
      return text;
    } catch (e) {
      AnxLog.severe('BookReview: load failed: $e');
      if (mounted && bookId == widget.bookId) {
        setState(() => _loading = false);
      }
      return null;
    }
  }

  Future<void> _openEditor() async {
    final latest = await _load();
    if (!mounted || latest == null) return;
    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (context) => BookReviewEditorPage(
          bookId: widget.bookId,
          bookTitle: widget.bookTitle,
          initialReview: latest,
        ),
      ),
    );

    if (!mounted) return;
    await _load();
    if (!mounted || result == null) return;

    // 备注变化后刷新书架（Book 模型带 review 字段）
    ref.read(bookListProvider.notifier).refresh();
    unawaited(ref
        .read(syncProvider.notifier)
        .syncData(SyncDirection.both, null, trigger: SyncTrigger.auto));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(syncDatabaseRevisionProvider, (_, __) => _load());
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final hasContent = _review.trim().isNotEmpty;

    return FilledContainer(
      width: MediaQuery.of(context).size.width,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      child: InkWell(
        onTap: _loading ? null : _openEditor,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rate_review_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.bookReviewSectionTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Icon(Icons.edit_outlined,
                    size: 18, color: theme.colorScheme.outline),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (!hasContent)
              Text(
                l10n.bookReviewEmptyHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              )
            else
              StyledMarkdown(data: _review),
          ],
        ),
      ),
    );
  }
}
