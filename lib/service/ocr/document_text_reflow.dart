/// Join visual line wraps for the reading preview only. The AI draft keeps the
/// exact extracted text. This is not table reconstruction or semantic layout.
String reflowDocumentText(String text) {
  final paragraphs = <String>[];
  var current = '';
  void flush() {
    if (current.isNotEmpty) paragraphs.add(current);
    current = '';
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (current.isNotEmpty &&
        (RegExp(r'[。！？.!?：:]$').hasMatch(current) ||
            RegExp(r'^\s{2,}').hasMatch(raw))) {
      flush();
    }
    if (current.isNotEmpty) {
      if (RegExp(r'[A-Za-z]-$').hasMatch(current) &&
          RegExp(r'^[a-z]').hasMatch(line)) {
        current = current.substring(0, current.length - 1);
      } else if (RegExp(r'[A-Za-z0-9,;]$').hasMatch(current) &&
          RegExp(r'^[A-Za-z0-9]').hasMatch(line)) {
        current += ' ';
      }
    }
    current += line;
  }
  flush();
  return paragraphs.join('\n\n');
}
