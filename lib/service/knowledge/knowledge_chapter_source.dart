typedef ChapterContentLoader = Future<String> Function(
  String href, {
  int? maxCharacters,
});

class KnowledgeChapterRef {
  const KnowledgeChapterRef({
    required this.id,
    required this.title,
    required this.href,
    this.children = const [],
  });

  final String id;
  final String title;
  final String href;
  final List<KnowledgeChapterRef> children;

  Iterable<KnowledgeChapterRef> flatten() sync* {
    yield this;
    for (final child in children) {
      yield* child.flatten();
    }
  }
}

/// Converts the reader's ordered table of contents into indexable chapter
/// text. The loader is supplied by the active reader/WebView bridge.
class KnowledgeChapterSource {
  KnowledgeChapterSource(Iterable<KnowledgeChapterRef> chapters, this._loader)
      : chapters = List.unmodifiable(
          chapters.expand((chapter) => chapter.flatten()),
        );

  final List<KnowledgeChapterRef> chapters;
  final ChapterContentLoader _loader;

  Future<Map<String, String>> load({int? maxCharacters}) async {
    final contents = <String, String>{};
    for (final chapter in chapters) {
      if (chapter.href.trim().isEmpty) continue;
      final content = await _loader(
        chapter.href,
        maxCharacters: maxCharacters,
      );
      if (content.trim().isNotEmpty) {
        contents[chapter.id] = content;
      }
    }
    return contents;
  }
}
