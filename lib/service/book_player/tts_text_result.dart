/// Only an explicit empty string means the navigator reached the book end.
/// A missing WebView reply is a transport failure, not a finished chapter/book.
String ttsTextResult(dynamic value, {Object? error}) {
  if (error != null || value is! String) {
    throw StateError('TTS reader did not return a valid text result');
  }
  return value;
}
