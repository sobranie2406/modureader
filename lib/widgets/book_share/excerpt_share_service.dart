import 'package:modu_reader/widgets/reading_page/reader_menu_appearance.dart';
import 'package:flutter/material.dart';
import 'package:modu_reader/widgets/book_share/excerpt_share_bottom_sheet.dart';

class ExcerptShareService {
  static Future<void> showShareExcerpt({
    required BuildContext context,
    required String bookTitle,
    required String author,
    required String excerpt,
    String? chapter,
    bool allowWindowAdjustment = false,
    bool readerAppearance = false,
  }) async {
    await showExcerptShareBottomSheet(
      context: context,
      bookTitle: bookTitle,
      author: author,
      excerpt: excerpt,
      chapter: chapter,
      allowWindowAdjustment: allowWindowAdjustment,
      readerAppearance:
          readerAppearance || ReaderMenuAppearance.translucent(context),
    );
  }
}
