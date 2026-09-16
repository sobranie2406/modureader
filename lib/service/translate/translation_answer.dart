/// Translation uses only the answer, never the model's reasoning envelope.
/// Also withhold unfinished reasoning and partial tags in streaming output.
String translationAnswer(String value) {
  final tags = RegExp(r'<\s*(/?)\s*think\s*>', caseSensitive: false);
  final answer = StringBuffer();
  var depth = 0;
  var offset = 0;
  for (final tag in tags.allMatches(value)) {
    if (tag.group(1) == '/') {
      // Some endpoints omit the opening tag when using a reasoning prefill.
      if (depth == 0) answer.clear();
      if (depth > 0) depth--;
    } else {
      if (depth == 0) answer.write(value.substring(offset, tag.start));
      depth++;
    }
    offset = tag.end;
  }
  if (depth == 0) answer.write(value.substring(offset));
  return answer
      .toString()
      .replaceFirst(
          RegExp(r'<\s*/?\s*(?:t|th|thi|thin|think)?\s*$',
              caseSensitive: false),
          '')
      .trim();
}
