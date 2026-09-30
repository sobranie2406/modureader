/// A spine section's range in the book-wide progress slider. This comes from
/// the reader's actual size-weighted section boundaries, not equal divisions.
class ReaderProgressChapter {
  const ReaderProgressChapter(
      {required this.number,
      required this.title,
      required this.start,
      required this.end});
  final int number;
  final String title;
  final double start, end;

  factory ReaderProgressChapter.fromJson(Map<String, dynamic> json) =>
      ReaderProgressChapter(
          number: (json['number'] as num).toInt(),
          title: json['title'] as String? ?? '',
          start: (json['start'] as num).toDouble(),
          end: (json['end'] as num).toDouble());
}

class ReaderProgress {
  const ReaderProgress(
      {this.percentage = 0,
      this.chapterTitle = '',
      this.currentChapter = 0,
      this.totalChapters = 0,
      this.currentPage = 0,
      this.totalPages = 0,
      this.chapters = const []});
  final double percentage;
  final String chapterTitle;
  final int currentChapter, totalChapters, currentPage, totalPages;
  final List<ReaderProgressChapter> chapters;
  bool get isReady => totalChapters > 0;
  String get chapterProgress => _ratio(currentChapter, totalChapters);
  String get chapterPageProgress => _ratio(currentPage, totalPages);
  static String _ratio(int current, int total) =>
      total > 0 ? '${current.clamp(1, total)}/$total' : '—';

  ReaderProgressChapter? chapterAt(double percentage) {
    if (chapters.isEmpty || !percentage.isFinite) return null;
    if (percentage <= 0) return chapters.first;
    // A shared boundary belongs to the following non-empty section.
    final available = chapters.where((c) => c.end > c.start).toList();
    for (final chapter in available) {
      if (percentage < chapter.end - 1e-12) return chapter;
    }
    return available.isEmpty ? chapters.last : available.last;
  }

  ReaderProgress copyWithChapters(List<ReaderProgressChapter> value) =>
      ReaderProgress(
          percentage: percentage,
          chapterTitle: chapterTitle,
          currentChapter: currentChapter,
          totalChapters: totalChapters,
          currentPage: currentPage,
          totalPages: totalPages,
          chapters: List.unmodifiable(value));
}
