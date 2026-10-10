import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum QuerySection {
  dictionary('字典', 'Dictionary'),
  encyclopedia('百科', 'Encyclopedia'),
  translation('翻译', 'Translation'),
  knowledge('AI 知识', 'AI knowledge'),
  classical('文言文翻译', 'Classical Chinese'),
  book('本书 AI', 'Book AI'),
  web('联网搜索', 'Web search');

  const QuerySection(this.zh, this.en);
  final String zh, en;
  static const comprehensive = [
    dictionary,
    encyclopedia,
    translation,
    knowledge
  ];
}

class UnifiedQueryPreferences {
  static const key = 'unifiedQueryPreferences';
  Set<QuerySection> included = QuerySection.comprehensive.toSet();
  bool smartOrder = true, useContext = true, manualAi = false;
  bool wikipedia = true, baiduLink = true;
  String knowledgePrompt = '', classicalPrompt = '';

  static UnifiedQueryPreferences load(SharedPreferences prefs) {
    final result = UnifiedQueryPreferences();
    try {
      final raw = jsonDecode(prefs.getString(key) ?? '{}');
      if (raw is! Map) return result;
      if (raw['included'] is List) {
        result.included = QuerySection.comprehensive
            .where((s) => (raw['included'] as List).contains(s.name))
            .toSet();
      }
      result.smartOrder = raw['smartOrder'] != false;
      result.useContext = raw['useContext'] != false;
      result.manualAi = raw['manualAi'] == true;
      result.wikipedia = raw['wikipedia'] != false;
      result.baiduLink = raw['baiduLink'] != false;
      for (final field in ['knowledgePrompt', 'classicalPrompt']) {
        final value = raw[field];
        if (value is String && value.length <= 8000) {
          if (field == 'knowledgePrompt') result.knowledgePrompt = value;
          if (field == 'classicalPrompt') result.classicalPrompt = value;
        }
      }
    } catch (_) {/* Invalid local settings use the defaults. */}
    return result;
  }

  Future<void> save(SharedPreferences prefs) async {
    if (!await prefs.setString(
        key,
        jsonEncode({
          'included': included.map((s) => s.name).toList(),
          'smartOrder': smartOrder,
          'useContext': useContext,
          'manualAi': manualAi,
          'wikipedia': wikipedia,
          'baiduLink': baiduLink,
          'knowledgePrompt': knowledgePrompt,
          'classicalPrompt': classicalPrompt,
        }))) {
      throw StateError('Could not save lookup preferences');
    }
  }
}

/// Local, predictable ordering: no model/network request to classify a query.
List<QuerySection> queryOrder(String text, UnifiedQueryPreferences prefs) {
  final query = text.trim();
  final sentence = query.length > 24 || RegExp(r'[。！？!?；;]').hasMatch(query);
  final shortChinese = RegExp(r'^[\u3400-\u9fff]{2,4}$').hasMatch(query);
  final order = !prefs.smartOrder
      ? QuerySection.comprehensive
      : sentence
          ? [
              QuerySection.translation,
              QuerySection.knowledge,
              QuerySection.dictionary,
              QuerySection.encyclopedia
            ]
          : shortChinese
              ? [
                  QuerySection.dictionary,
                  QuerySection.encyclopedia,
                  QuerySection.knowledge,
                  QuerySection.translation
                ]
              : [
                  QuerySection.dictionary,
                  QuerySection.translation,
                  QuerySection.encyclopedia,
                  QuerySection.knowledge
                ];
  return order.where(prefs.included.contains).toList();
}
