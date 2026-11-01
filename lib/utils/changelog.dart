import 'package:pub_semver/pub_semver.dart';

/// Select the releases missed by this installation, ignoring build metadata.
String changelogSince(String markdown,
    {required String previous,
    required String current,
    required bool chinese}) {
  Version parse(String value) => Version.parse(value.split('+').first);
  Version now;
  Version? before;
  try {
    now = parse(current);
  } on FormatException {
    return '';
  }
  try {
    before = parse(previous);
  } on FormatException {
    before = null;
  }
  final headings = RegExp(r'^## ([^\s]+)\s*$', multiLine: true)
      .allMatches(markdown)
      .toList();
  final sections = <({Version version, String text})>[];
  for (var i = 0; i < headings.length; i++) {
    final heading = headings[i];
    Version version;
    try {
      version = Version.parse(heading.group(1)!);
    } on FormatException {
      continue;
    }
    if (version > now ||
        (now.preRelease.isEmpty && version.preRelease.isNotEmpty)) {
      continue;
    }
    final upgrading = before != null && before < now;
    if (upgrading ? version <= before : version != now) continue;
    final body = markdown.substring(heading.end,
        i + 1 < headings.length ? headings[i + 1].start : markdown.length);
    final languages = RegExp(r'^### (English|简体中文)\s*$', multiLine: true)
        .allMatches(body)
        .toList();
    String text;
    if (languages.isNotEmpty) {
      final index = languages
          .indexWhere((m) => m.group(1) == (chinese ? '简体中文' : 'English'));
      // A missing translation must not hide the release's changes.
      final selected = index < 0 ? 0 : index;
      text = body.substring(
          languages[selected].end,
          selected + 1 < languages.length
              ? languages[selected + 1].start
              : body.length);
    } else {
      // Before 1.2.0 the bundled history uses equal English/Chinese bullet blocks.
      final bullets = body
          .split('\n')
          .where((line) =>
              line.trimLeft().startsWith('- ') ||
              line.trimLeft().startsWith('* '))
          .toList();
      final midpoint = bullets.length ~/ 2;
      text =
          (chinese ? bullets.sublist(midpoint) : bullets.sublist(0, midpoint))
              .join('\n');
    }
    if (text.trim().isNotEmpty) {
      sections.add((version: version, text: '## $version\n\n${text.trim()}'));
    }
  }
  sections.sort((a, b) => b.version.compareTo(a.version));
  return sections.map((section) => section.text).join('\n\n');
}
