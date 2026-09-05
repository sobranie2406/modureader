import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef CurrentChapterContentFetcher = Future<String> Function(
    {int? maxCharacters});
typedef ChapterContentByHrefFetcher = Future<String> Function(
  String href, {
  int? maxCharacters,
});
typedef PreviousContentFetcher = Future<String> Function({int? maxCharacters});

class ChapterContentHandlers {
  const ChapterContentHandlers({
    required this.fetchCurrentChapter,
    required this.fetchChapterByHref,
    required this.fetchPreviousContent,
  });

  final CurrentChapterContentFetcher fetchCurrentChapter;
  final ChapterContentByHrefFetcher fetchChapterByHref;
  final PreviousContentFetcher fetchPreviousContent;
}

final chapterContentBridgeProvider =
    StateProvider<ChapterContentHandlers?>((ref) => null);
