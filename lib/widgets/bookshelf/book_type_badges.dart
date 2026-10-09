import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/models/document_reading_mode.dart';
import 'package:anx_reader/service/book_player/document_reading_mode_store.dart';
import 'package:anx_reader/service/book_player/document_type_store.dart';
import 'package:anx_reader/service/book_source_format.dart';
import 'package:flutter/material.dart';

/// Painting uses cached metadata; legacy conversion detection runs off-isolate.
class BookTypeBadges extends StatefulWidget {
  const BookTypeBadges({super.key, required this.book});
  final Book book;

  static String formatFor(Book book) =>
      BookSourceFormat(Prefs().prefs).format(book);

  @override
  State<BookTypeBadges> createState() => _BookTypeBadgesState();

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
        'UMD' => const Color(0xFF936536),
        _ => const Color(0xFF52667A),
      };
}

class _BookTypeBadgesState extends State<BookTypeBadges> {
  late Future<String> _format;

  @override
  void initState() {
    super.initState();
    _format = BookSourceFormat(Prefs().prefs).resolve(widget.book);
  }

  @override
  void didUpdateWidget(BookTypeBadges oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.book, widget.book)) {
      _format = BookSourceFormat(Prefs().prefs).resolve(widget.book);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
      future: _format,
      builder: (context, snapshot) => ListenableBuilder(
            listenable: Prefs(),
            builder: (context, _) {
              final format = snapshot.connectionState == ConnectionState.done
                  ? snapshot.data ?? BookTypeBadges.formatFor(widget.book)
                  : BookTypeBadges.formatFor(widget.book);
              if (format.isEmpty) return const SizedBox.shrink();
              final labels = <(String, Color)>[
                (format, BookTypeBadges.formatColor(format)),
                if (BookTypeBadges.scanned(widget.book))
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
                        constraints:
                            BoxConstraints(maxWidth: constraints.maxWidth),
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
          ));
}
