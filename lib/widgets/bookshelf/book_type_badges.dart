import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/models/document_reading_mode.dart';
import 'package:anx_reader/service/book_player/document_reading_mode_store.dart';
import 'package:anx_reader/service/book_player/document_type_store.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

/// Cheap cached metadata only: painting the shelf never opens a book to inspect it.
class BookTypeBadges extends StatelessWidget {
  const BookTypeBadges({super.key, required this.book});
  final Book book;

  static String formatFor(Book book) {
    final extension =
        path.extension(book.filePath).replaceFirst('.', '').toUpperCase();
    return extension == 'MARKDOWN' ? 'MD' : extension;
  }

  static bool scanned(Book book) {
    final prefs = Prefs().prefs;
    final mode = DocumentReadingModeStore(prefs).read(book);
    if (mode == DocumentReadingMode.imageEpub) return true;
    if (mode != DocumentReadingMode.pdf) return false;
    final store = DocumentTypeStore(prefs);
    final kind = store.read(customCssBookKey(book)) ??
        store.readDetected(customCssBookKey(book));
    return kind == 'scanned' || kind == 'image-with-text';
  }

  static Color formatColor(String format) => switch (format) {
        'PDF' => const Color(0xFF2463CB),
        'EPUB' => const Color(0xFF087F83),
        'FB2' => const Color(0xFF7851AF),
        'TXT' => const Color(0xFF52667A),
        'MOBI' => const Color(0xFF8A5636),
        'AZW3' => const Color(0xFF4D55AC),
        'MD' => const Color(0xFF287A97),
        _ => const Color(0xFF52667A),
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Prefs(),
        builder: (context, _) {
          final format = formatFor(book);
          if (format.isEmpty) return const SizedBox.shrink();
          final labels = <(String, Color)>[
            (format, formatColor(format)),
            if (scanned(book))
              (
                ModuStrings.text(context, '扫描版', 'Scanned'),
                const Color(0xFFAC5B00)
              ),
          ];
          return IgnorePointer(
              child: LayoutBuilder(builder: (context, constraints) {
            return Wrap(
              spacing: 4,
              runSpacing: 4,
              verticalDirection: VerticalDirection.up,
              children: [
                for (final (label, color) in labels)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Prefs().eInkMode ? Colors.white : color,
                          borderRadius: BorderRadius.circular(6),
                          border: Prefs().eInkMode
                              ? Border.all(color: Colors.black)
                              : null,
                        ),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            child: Text(label,
                                style: TextStyle(
                                    color: Prefs().eInkMode
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 10,
                                    height: 1.1,
                                    fontWeight: FontWeight.w600))),
                      ),
                    ),
                  ),
              ],
            );
          }));
        },
      );
}
