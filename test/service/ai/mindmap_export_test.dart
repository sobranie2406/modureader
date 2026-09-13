import 'dart:convert';
import 'dart:ui' as ui;
import 'package:anx_reader/service/ai/mindmap_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

Map<String, dynamic> fixture() => {
      'title': '标题 / 测试',
      'root': {
        'id': 'duplicate',
        'label': 'Root <&> "中文"',
        'children': [
          {
            'id': 'duplicate',
            'label': 'Child **one**',
            'children': [
              {'label': '末尾节点', 'children': []},
            ]
          },
          {
            'label': 'Second\nline & <script>not executable</script>',
            'children': []
          },
        ]
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('JSON retains all levels, the single root and unique IDs', () async {
    final doc = MindmapExportDocument.fromJson(fixture());
    final data =
        jsonDecode(utf8.decode(await doc.export(MindmapExportFormat.json)));
    expect(data['title'], '标题 / 测试');
    expect(data['root']['label'], 'Root <&> "中文"');
    expect(data['root']['children'][0]['children'][0]['label'], '末尾节点');
    expect(data['root']['id'], isNot(data['root']['children'][0]['id']));
  });
  test('FreeMind XML escapes labels and preserves hierarchy', () async {
    final doc = MindmapExportDocument.fromJson(fixture());
    final xml = XmlDocument.parse(
        utf8.decode(await doc.export(MindmapExportFormat.freeMind)));
    expect(xml.rootElement.name.local, 'map');
    expect(xml.findAllElements('node').length, 4);
    expect(xml.findAllElements('node').first.getAttribute('TEXT'),
        'Root <&> "中文"');
    expect(xml.findAllElements('node').last.getAttribute('TEXT'),
        'Second\nline & <script>not executable</script>');
    expect(xml.findAllElements('script'), isEmpty);
  });
  test('Markdown keeps hierarchy and escapes injected markup', () async {
    final text = utf8.decode(await MindmapExportDocument.fromJson(fixture())
        .export(MindmapExportFormat.markdown));
    expect(text, contains('    - 末尾节点'));
    expect(text, contains(r'Child \*\*one\*\*'));
    expect(text, contains(r'\<script\>'));
  });
  test('SVG exports every node and its last line, without executable markup',
      () async {
    final xml = XmlDocument.parse(utf8.decode(
        await MindmapExportDocument.fromJson(fixture())
            .export(MindmapExportFormat.svg)));
    expect(xml.rootElement.name.local, 'svg');
    expect(xml.findAllElements('path').length, 3);
    expect(xml.findAllElements('rect').length, 5);
    final labels = xml.findAllElements('text').map((e) => e.innerText).join('');
    expect(labels, contains('末尾节点'));
    expect(labels, contains('not executable'));
    expect(xml.findAllElements('script'), isEmpty);
  });
  test('PNG is a decodable full-map image with bounded dimensions', () async {
    final bytes = await MindmapExportDocument.fromJson(fixture())
        .export(MindmapExportFormat.png);
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, greaterThan(600));
    expect(frame.image.width, lessThanOrEqualTo(8192));
    expect(frame.image.height, lessThanOrEqualTo(8192));
    frame.image.dispose();
    codec.dispose();
  });
  test('filenames cannot escape destination and names remain unique', () {
    final doc = MindmapExportDocument.fromJson(fixture());
    final name = doc.fileName(MindmapExportFormat.png, now: DateTime(2026));
    expect(name, startsWith('Modu-'));
    expect(name, endsWith('.png'));
    expect(name, isNot(contains('/')));
    expect(name,
        isNot(doc.fileName(MindmapExportFormat.png, now: DateTime(2027))));
  });
  test('invalid and excessively deep AI trees fail safely', () {
    expect(() => MindmapExportDocument.fromJson({'root': {}}),
        throwsFormatException);
    Map<String, dynamic> node = {'label': 'end'};
    for (var i = 0; i < 70; i++) {
      node = {
        'label': 'node',
        'children': [node]
      };
    }
    expect(() => MindmapExportDocument.fromJson({'root': node}),
        throwsFormatException);
  });
}
