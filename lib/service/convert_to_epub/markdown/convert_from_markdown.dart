import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

Future<File> convertFromMarkdown(File file) async {
  if (await file.length() > 64 * 1024 * 1024) {
    throw const FormatException('Markdown file exceeds 64 MB');
  }
  final source = await file.readAsString(encoding: utf8);
  final bytes = await compute(
    _convert,
    (source, path.basenameWithoutExtension(file.path)),
  );
  final temp = await getAnxTempDir();
  // Never derive temporary paths from untrusted titles or overwrite the source.
  final output =
      File(path.join(temp.path, 'markdown-${const Uuid().v4()}.epub'));
  return output.writeAsBytes(bytes, flush: true);
}

List<int> _convert((String, String) input) =>
    markdownToEpub(input.$1, fallbackTitle: input.$2);

const _xhtml = 'http://www.w3.org/1999/xhtml';
const _allowedTags = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'strong',
  'em',
  'del',
  's',
  'blockquote',
  'ul',
  'ol',
  'li',
  'pre',
  'code',
  'br',
  'hr',
  'a',
  'img',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'th',
  'td',
  'span',
  'div',
  'sup',
  'sub',
  'b',
  'i',
  'u',
  'dl',
  'dt',
  'dd',
  'kbd',
  'mark',
};
const _dropTags = {
  'script',
  'style',
  'iframe',
  'object',
  'embed',
  'svg',
  'math',
  'form',
  'link',
  'meta',
  'base',
  'video',
  'audio',
  'source',
};

class _Chapter {
  _Chapter(this.title, this.level);
  final String title;
  final int level;
  final nodes = <XmlNode>[];
}

/// Builds a self-contained EPUB without evaluating HTML or fetching resources.
/// UTF-8 Markdown and embedded PNG/JPEG/GIF/WebP images are supported. External
/// images become labelled links, relative images become readable placeholders:
/// single-file mobile imports do not grant access to sibling resource folders.
List<int> markdownToEpub(String source, {required String fallbackTitle}) {
  source = source
      .replaceFirst(RegExp(r'^\uFEFF'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  if (source.trim().isEmpty) {
    throw const FormatException('Markdown book is empty');
  }
  final fragment = html.parseFragment(
      md.markdownToHtml(source, extensionSet: md.ExtensionSet.gitHubWeb));
  final title = fragment.querySelector('h1')?.text.trim();
  final bookTitle = title != null && title.isNotEmpty ? title : fallbackTitle;
  final chapters = <_Chapter>[];
  final anchors = <String, int>{};
  final usedIds = <String>{};
  final resources = <String, (String, List<int>)>{};
  var chapter = _Chapter(bookTitle, 1);
  var chapterLength = 0;

  String uniqueId(String preferred) {
    final base = preferred.isEmpty ? 'section' : preferred;
    var id = base;
    var suffix = 1;
    while (!usedIds.add(id)) {
      id = '$base-${suffix++}';
    }
    return id;
  }

  XmlNode? sanitize(dom.Node node) {
    if (node is dom.Text) return XmlText(_xmlText(node.data));
    if (node is! dom.Element || _dropTags.contains(node.localName)) return null;
    var tag = node.localName ?? 'span';
    if (tag == 'input') {
      return node.attributes['type'] == 'checkbox'
          ? XmlText(node.attributes.containsKey('checked') ? '☑ ' : '☐ ')
          : null;
    }
    if (!_allowedTags.contains(tag)) tag = 'span';
    final attrs = <XmlAttribute>[];
    final preferredId = node.id;
    if (preferredId.isNotEmpty) {
      final id = uniqueId(preferredId);
      anchors.putIfAbsent(preferredId, () => chapters.length);
      anchors[id] = chapters.length;
      attrs.add(XmlAttribute(XmlName('id'), _xmlText(id)));
    }
    final hint = node.attributes['title'];
    if (hint != null) attrs.add(XmlAttribute(XmlName('title'), _xmlText(hint)));
    if (tag == 'a') {
      final href = _safeLink(node.attributes['href']);
      if (href != null) attrs.add(XmlAttribute(XmlName('href'), href));
    }
    if (tag == 'img') {
      final alt = _xmlText(node.attributes['alt'] ?? 'Image');
      final src = node.attributes['src'] ?? '';
      final embedded = _embeddedImage(src);
      if (embedded != null) {
        final filename =
            'images/${resources.length}.${embedded.$1.split('/').last}';
        resources[filename] = embedded;
        attrs.addAll([
          XmlAttribute(XmlName('src'), '../$filename'),
          XmlAttribute(XmlName('alt'), alt),
        ]);
      } else {
        final link = _safeLink(src);
        return XmlElement(
            XmlName(link != null && !link.startsWith('#') ? 'a' : 'span'), [
          if (link != null && !link.startsWith('#'))
            XmlAttribute(XmlName('href'), link)
        ], [
          XmlText('[${alt.isEmpty ? 'Image' : alt}]')
        ]);
      }
    }
    if (tag == 'ol' || tag == 'li') {
      final key = tag == 'ol' ? 'start' : 'value';
      final value = int.tryParse(node.attributes[key] ?? '');
      if (value != null) attrs.add(XmlAttribute(XmlName(key), '$value'));
    }
    if (tag == 'th' || tag == 'td') {
      final align = node.attributes['align'];
      if (const ['left', 'center', 'right'].contains(align)) {
        attrs.add(XmlAttribute(XmlName('style'), 'text-align:$align'));
      }
    }
    final result = XmlElement(XmlName(tag), attrs);
    for (final child in node.nodes) {
      final safe = sanitize(child);
      if (safe != null) result.children.add(safe);
    }
    return result;
  }

  for (final node in fragment.nodes) {
    if (node is dom.Text && node.data.trim().isEmpty) continue;
    final heading = node is dom.Element &&
        RegExp(r'^h[1-6]$').hasMatch(node.localName ?? '');
    if (heading || chapterLength > 20000) {
      if (chapter.nodes.isNotEmpty) chapters.add(chapter);
      chapter = _Chapter(
          heading ? node.text.trim() : '$bookTitle (${chapters.length + 1})',
          heading ? int.parse(node.localName!.substring(1)) : 1);
      chapterLength = 0;
    }
    final safe = sanitize(node);
    if (safe != null) {
      chapter.nodes.add(safe);
      chapterLength += node.text?.length ?? 0;
    }
  }
  if (chapter.nodes.isNotEmpty) chapters.add(chapter);
  if (chapters.isEmpty) {
    throw const FormatException('Markdown book has no readable content');
  }

  // Fragment links must still work after headings have become separate files.
  for (final chapter in chapters) {
    for (final root in chapter.nodes) {
      final elements = [
        if (root is XmlElement) root,
        ...root.descendants.whereType<XmlElement>()
      ];
      for (final element in elements.where((e) => e.name.local == 'a')) {
        final href = element.getAttribute('href');
        if (href == null || !href.startsWith('#')) continue;
        final anchor = Uri.tryParse(href)?.fragment;
        final target = anchors[anchor];
        if (target != null) element.setAttribute('href', '$target.xhtml$href');
      }
    }
  }
  final archive = Archive();
  void add(String name, String content, {bool compress = true}) {
    final bytes = utf8.encode(content);
    archive
        .addFile(ArchiveFile(name, bytes.length, bytes)..compress = compress);
  }

  add('mimetype', 'application/epub+zip', compress: false);
  add(
      'META-INF/container.xml',
      '<?xml version="1.0" encoding="UTF-8"?>'
          '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
          '</rootfiles></container>');
  String document(void Function(XmlBuilder) build) {
    final builder = XmlBuilder()
      ..processing('xml', 'version="1.0" encoding="UTF-8"');
    build(builder);
    return builder.buildDocument().toXmlString();
  }

  final identifier = 'urn:sha256:${sha256.convert(utf8.encode(source))}';
  add('OEBPS/content.opf', document((b) {
    b.element('package', attributes: {
      'xmlns': 'http://www.idpf.org/2007/opf',
      'version': '3.0',
      'unique-identifier': 'book-id'
    }, nest: () {
      b.element('metadata',
          attributes: {'xmlns:dc': 'http://purl.org/dc/elements/1.1/'},
          nest: () {
        b.element('dc:identifier',
            attributes: {'id': 'book-id'}, nest: identifier);
        b.element('dc:title', nest: _xmlText(bookTitle));
        b.element('dc:language', nest: 'und');
        b.element('meta',
            attributes: {'property': 'dcterms:modified'},
            nest: '2000-01-01T00:00:00Z');
      });
      b.element('manifest', nest: () {
        b.element('item', attributes: {
          'id': 'nav',
          'href': 'nav.xhtml',
          'media-type': 'application/xhtml+xml',
          'properties': 'nav'
        });
        b.element('item', attributes: {
          'id': 'css',
          'href': 'style.css',
          'media-type': 'text/css'
        });
        for (var i = 0; i < chapters.length; i++) {
          b.element('item', attributes: {
            'id': 'c$i',
            'href': 'xhtml/$i.xhtml',
            'media-type': 'application/xhtml+xml'
          });
        }
        for (final entry in resources.entries) {
          b.element('item', attributes: {
            'id': 'image${resources.keys.toList().indexOf(entry.key)}',
            'href': entry.key,
            'media-type': entry.value.$1
          });
        }
      });
      b.element('spine', nest: () {
        for (var i = 0; i < chapters.length; i++) {
          b.element('itemref', attributes: {'idref': 'c$i'});
        }
      });
    });
  }));
  add('OEBPS/nav.xhtml', document((b) {
    b.element('html', attributes: {
      'xmlns': _xhtml,
      'xmlns:epub': 'http://www.idpf.org/2007/ops'
    }, nest: () {
      b.element('head', nest: () {
        b.element('title', nest: _xmlText(bookTitle));
      });
      b.element('body', nest: () {
        b.element('nav', attributes: {'epub:type': 'toc'}, nest: () {
          // A stack produces nested navigation even when heading levels skip.
          var index = 0;
          void list(int level) {
            b.element('ol', nest: () {
              while (
                  index < chapters.length && chapters[index].level >= level) {
                final current = index++;
                b.element('li', nest: () {
                  b.element('a',
                      attributes: {'href': 'xhtml/$current.xhtml'},
                      nest: _xmlText(chapters[current].title));
                  if (index < chapters.length &&
                      chapters[index].level > chapters[current].level) {
                    list(chapters[index].level);
                  }
                });
              }
            });
          }

          list(1);
        });
      });
    });
  }));
  add(
      'OEBPS/style.css',
      'img { max-width:100%; height:auto; } pre { white-space:pre-wrap; overflow-wrap:anywhere; } '
          'table { border-collapse:collapse; max-width:100%; } td,th { border:1px solid currentColor; padding:.3em; } '
          'blockquote { margin-inline:1em; padding-inline-start:1em; border-inline-start:2px solid currentColor; }');
  for (var i = 0; i < chapters.length; i++) {
    add('OEBPS/xhtml/$i.xhtml', document((b) {
      b.element('html', attributes: {'xmlns': _xhtml}, nest: () {
        b.element('head', nest: () {
          b.element('title', nest: _xmlText(chapters[i].title));
          b.element('link', attributes: {
            'rel': 'stylesheet',
            'href': '../style.css',
            'type': 'text/css'
          });
        });
        b.element('body', nest: () {
          for (final node in chapters[i].nodes) {
            b.xml(node.toXmlString());
          }
        });
      });
    }));
  }
  for (final entry in resources.entries) {
    archive.addFile(ArchiveFile(
        'OEBPS/${entry.key}', entry.value.$2.length, entry.value.$2));
  }
  return ZipEncoder().encode(archive)!;
}

String _xmlText(String text) => String.fromCharCodes(text.runes.where((r) =>
    r == 9 ||
    r == 10 ||
    r == 13 ||
    (r >= 0x20 && r <= 0xd7ff) ||
    (r >= 0xe000 && r <= 0xfffd) ||
    (r >= 0x10000 && r <= 0x10ffff)));

String? _safeLink(String? value) {
  if (value == null || value.contains(RegExp(r'[\x00-\x20\x7f]'))) return null;
  if (value.startsWith('#')) return value;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const ['https', 'http', 'mailto'].contains(uri.scheme.toLowerCase())) {
    return null;
  }
  if (uri.scheme != 'mailto' && (uri.host.isEmpty || uri.userInfo.isNotEmpty)) {
    return null;
  }
  return value;
}

(String, List<int>)? _embeddedImage(String src) {
  if (src.length > 8 * 1024 * 1024) return null;
  final match = RegExp(
          r'^data:(image/(?:png|jpeg|gif|webp));base64,([a-zA-Z0-9+/=\r\n]+)$')
      .firstMatch(src);
  if (match == null) return null;
  try {
    final bytes = base64.decode(match[2]!.replaceAll(RegExp(r'\s'), ''));
    if (bytes.isEmpty) return null;
    return (match[1]!, bytes);
  } on FormatException {
    return null;
  }
}
