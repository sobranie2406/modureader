import 'dart:typed_data';

import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/weread/weread_api.dart';
import 'package:modu_reader/widgets/book_detail_typography.dart';
import 'package:flutter/material.dart';
import 'weread_common.dart';

class WereadInfoPanel extends StatelessWidget {
  const WereadInfoPanel({
    super.key,
    required this.info,
    this.coverAction,
    this.descriptionAction,
    this.apiFactory,
  });

  final Map<String, dynamic> info;
  final Widget? coverAction, descriptionAction;
  final WereadApi Function(String)? apiFactory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = wereadLink(info['cover'], cover: true);
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cover != null) ...[
          Center(
            child: _WereadCover(
              key: ValueKey(cover.toString()),
              url: cover.toString(),
              apiFactory: apiFactory,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(wereadText(info['title']),
            textAlign: TextAlign.center,
            style: BookDetailTypography.title(context)),
        const SizedBox(height: 8),
        Text(wereadText(info['author']),
            textAlign: TextAlign.center,
            style: BookDetailTypography.author(context)),
        if (coverAction != null)
          Align(alignment: Alignment.center, child: coverAction!),
        const SizedBox(height: 24),
        _rating(context),
        if (info['wordCount'] != null) ...[
          const Divider(height: 32),
          Text(
              ModuStrings.text(context, '字数：${info['wordCount']}',
                  'Word count: ${info['wordCount']}'),
              style: theme.textTheme.bodyMedium),
        ],
      ],
    );
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(ModuStrings.text(context, '简介', 'Description'),
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        SelectableText(
          wereadText(info['intro']).isEmpty
              ? ModuStrings.text(context, '接口未提供简介', 'No description provided')
              : wereadText(info['intro']),
          style: theme.textTheme.bodyMedium,
        ),
        if (descriptionAction != null)
          Align(alignment: Alignment.centerLeft, child: descriptionAction!),
        const Divider(height: 32),
        Text(ModuStrings.text(context, '出版信息', 'Publication details'),
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        wereadPublication(context, info, includeIdentity: false),
      ],
    );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 760 &&
          MediaQuery.textScalerOf(context).scale(16) <= 24) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: identity),
            const SizedBox(width: 32),
            Expanded(child: description),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [identity, const Divider(height: 32), description],
      );
    });
  }

  Widget _rating(BuildContext context) {
    final theme = Theme.of(context);
    final detail = wereadMap(info['newRatingDetail']);
    final total = ['good', 'fair', 'poor']
        .fold<int>(0, (sum, name) => sum + wereadInt(detail[name]));
    final labels = {
      'good': ModuStrings.text(context, '推荐', 'Recommended'),
      'fair': ModuStrings.text(context, '一般', 'Fair'),
      'poor': ModuStrings.text(context, '不行', 'Not recommended'),
    };
    final score = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          info['newRating'] == null
              ? ModuStrings.text(context, '接口未提供推荐值', 'Rating not provided')
              : '${info['newRating']}%',
          style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
            ModuStrings.text(context, '${info['newRatingCount']} 人点评',
                '${info['newRatingCount']} ratings'),
            style: theme.textTheme.bodySmall),
      ],
    );
    final bars = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in labels.entries)
          if (detail.containsKey(entry.key))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${entry.value} (${detail[entry.key]})',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value:
                        total == 0 ? 0 : wereadInt(detail[entry.key]) / total,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(4),
                    semanticsLabel: entry.value,
                  ),
                ],
              ),
            ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(ModuStrings.text(context, '微信读书推荐值', 'WeRead rating'),
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          if (detail.isEmpty) return score;
          if (constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(16) > 24) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [score, const SizedBox(height: 12), bars],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(child: score),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: bars),
            ],
          );
        }),
      ],
    );
  }
}

class _WereadCover extends StatefulWidget {
  const _WereadCover({super.key, required this.url, this.apiFactory});
  final String url;
  final WereadApi Function(String)? apiFactory;

  @override
  State<_WereadCover> createState() => _WereadCoverState();
}

class _WereadCoverState extends State<_WereadCover> {
  late final _api = widget.apiFactory?.call('') ?? WereadApi('');
  late final _bytes = _api.cover(widget.url).whenComplete(_api.close);

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Center(
          child: Icon(Icons.menu_book_outlined,
              size: 64,
              semanticLabel: ModuStrings.text(
                  context, '微信读书封面暂不可用', 'WeRead cover unavailable')),
        );
    return SizedBox(
      width: 160,
      height: 224,
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) => snapshot.hasData
            ? Image.memory(
                snapshot.data!,
                fit: BoxFit.contain,
                cacheWidth: 480,
                semanticLabel:
                    ModuStrings.text(context, '微信读书封面', 'WeRead cover'),
                errorBuilder: (_, __, ___) => placeholder(),
              )
            : placeholder(),
      ),
    );
  }
}
