import 'dart:convert';

class SelectionSearchEngine {
  const SelectionSearchEngine(this.id, this.name, this.template);
  final String id, name, template;

  static const builtins = [
    SelectionSearchEngine('baidu', '百度', 'https://www.baidu.com/s?wd={query}'),
    SelectionSearchEngine(
        'bing', 'Bing', 'https://www.bing.com/search?q={query}'),
    SelectionSearchEngine(
        'google', 'Google', 'https://www.google.com/search?q={query}'),
    SelectionSearchEngine(
        'baike', '百度百科', 'https://baike.baidu.com/search/word?word={query}'),
    SelectionSearchEngine('wikipedia', '维基百科',
        'https://zh.wikipedia.org/w/index.php?search={query}'),
  ];

  String label(bool chinese) => chinese
      ? name
      : switch (id) {
          'baidu' => 'Baidu',
          'baike' => 'Baidu Baike',
          'wikipedia' => 'Wikipedia',
          _ => name,
        };

  static bool allowsNavigation(Uri? uri) =>
      uri != null &&
      ['https', 'http'].contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;

  void validate() {
    final uri = Uri.tryParse(template.replaceAll('{query}', 'modu'));
    if (id.isEmpty ||
        id.length > 100 ||
        name.trim().isEmpty ||
        name.length > 60 ||
        template.length > 2048 ||
        !template.contains('{query}') ||
        !allowsNavigation(uri) ||
        Uri.parse(template.replaceAll('{query}', 'other')).authority !=
            uri!.authority) {
      throw const FormatException('Invalid search engine');
    }
  }

  Uri search(String text) {
    validate();
    return Uri.parse(
        template.replaceAll('{query}', Uri.encodeComponent(text.trim())));
  }

  Map<String, String> toJson() =>
      {'id': id, 'name': name, 'template': template};
  static SelectionSearchEngine fromJson(dynamic data) {
    if (data is! Map ||
        data['id'] is! String ||
        data['name'] is! String ||
        data['template'] is! String) {
      throw const FormatException('Invalid search engine');
    }
    final engine =
        SelectionSearchEngine(data['id'], data['name'], data['template']);
    engine.validate();
    return engine;
  }
}

class SelectionSearchConfig {
  const SelectionSearchConfig(
      {this.selectedId = 'bing', this.custom = const []});
  final String selectedId;
  final List<SelectionSearchEngine> custom;
  List<SelectionSearchEngine> get engines =>
      [...SelectionSearchEngine.builtins, ...custom];
  SelectionSearchEngine get selected =>
      engines.firstWhere((e) => e.id == selectedId,
          orElse: () => SelectionSearchEngine.builtins[1]);

  void validate() {
    final ids = SelectionSearchEngine.builtins.map((e) => e.id).toSet();
    if (custom.length > 20) {
      throw const FormatException('Too many search engines');
    }
    for (final engine in custom) {
      engine.validate();
      if (!ids.add(engine.id)) {
        throw const FormatException('Duplicate search engine');
      }
    }
    if (!ids.contains(selectedId)) {
      throw const FormatException('Unknown search engine');
    }
  }

  String encode() {
    validate();
    return jsonEncode({
      'selectedId': selectedId,
      'custom': custom.map((e) => e.toJson()).toList()
    });
  }

  static SelectionSearchConfig decode(String text) {
    final data = jsonDecode(text);
    if (data is! Map ||
        data['selectedId'] is! String ||
        data['custom'] is! List) {
      throw const FormatException('Invalid search settings');
    }
    final config = SelectionSearchConfig(
        selectedId: data['selectedId'],
        custom: (data['custom'] as List)
            .map(SelectionSearchEngine.fromJson)
            .toList());
    config.validate();
    return config;
  }
}
