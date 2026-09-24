// Skip only separators, not arbitrary text whose synthesis happens to fail.
// Keep symbols (e.g. mathematical operators) and all scripts/numbers eligible
// for speech; an ASCII/CJK allowlist would silently drop other languages.
// U+22EF is also commonly used as an ellipsis, though Unicode calls it a symbol.
final _separatorOnly = RegExp(r'^[\p{P}\p{Z}\p{Cc}\p{Cf}\s⋯]*$', unicode: true);

bool isTtsSeparator(String text) => _separatorOnly.hasMatch(text);
