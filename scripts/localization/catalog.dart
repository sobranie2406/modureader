// Source extraction and generation for newer UI strings and bundled prompts.
// Run with: dart run scripts/localization/catalog.dart extract|generate
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

final entries = <String, Map<String, String>>{};
final chinese = RegExp(r'[\u3400-\u9fff]');
String keyFor(String text) {
  var hash = 2166136261;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 16777619) & 0xffffffff;
  }
  return 'ui_${hash.toRadixString(16)}';
}

void add(String zh, [String? en]) {
  if (!chinese.hasMatch(zh)) return;
  final key = keyFor(zh);
  final old = entries[key];
  if (old != null && old['zh'] != zh) throw StateError('Key collision: $zh');
  entries[key] = {'zh': zh, if (en != null) 'en': en, ...?old};
}

class Extract extends RecursiveAstVisitor<void> {
  Extract(this.path);
  final String path;
  String? literal(Expression value) =>
      value is StringLiteral ? value.stringValue : null;

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    final yes = literal(node.thenExpression), no = literal(node.elseExpression);
    if (yes != null &&
        no != null &&
        chinese.hasMatch(yes) &&
        !chinese.hasMatch(no)) {
      add(yes, no);
    }
    super.visitConditionalExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final args = node.argumentList.arguments;
    final positional = args.where((arg) => arg is! NamedExpression).toList();
    if ((['t', '_t', '_tr', '_text', '_label', 'dictionaryLabel']
                .contains(node.methodName.name) ||
            node.target?.toSource() == 'ModuStrings' &&
                ['text', 'format'].contains(node.methodName.name)) &&
        positional.length >= 2) {
      final zh = literal(positional[positional.length - 2]),
          en = literal(positional.last);
      if (zh != null && en != null) add(zh, en);
    }
    // Implicit constructor calls are parsed as method invocations without resolution.
    if (['ReadAnySkill', 'SelectionToolbarItem']
        .contains(node.methodName.name)) {
      _prompt(node.methodName.name, args);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitRecordLiteral(RecordLiteral node) {
    if (path.endsWith('/dictionary_common.dart') && node.fields.length == 2) {
      final zh = literal(node.fields.first), en = literal(node.fields.last);
      if (zh != null && en != null) add(zh, en);
    }
    super.visitRecordLiteral(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _prompt(
        node.constructorName.type.name2.lexeme, node.argumentList.arguments);
    super.visitInstanceCreationExpression(node);
  }

  void _prompt(String type, NodeList<Expression> args) {
    if (type == 'CustomCssProfile') {
      for (final arg in args.whereType<NamedExpression>()) {
        if (arg.name.label.name == 'name' && arg.expression is StringLiteral) {
          add((arg.expression as StringLiteral).stringValue!);
        }
      }
    }
    if (type != 'ReadAnySkill' && type != 'SelectionToolbarItem') return;
    final fields = <String, String>{};
    for (final arg in args.whereType<NamedExpression>()) {
      final value = literal(arg.expression);
      if (value != null) fields[arg.name.label.name] = value;
    }
    final id = type == 'ReadAnySkill'
        ? fields['id']
        : (args.isEmpty ? null : literal(args.first));
    if (id == null) return;
    for (final field in ['name', 'description', 'prompt']) {
      final value = fields[field];
      if (value != null && value.isNotEmpty) {
        entries[
            '${type == 'ReadAnySkill' ? 'skill' : 'selection'}_${id}_$field'] = {
          chinese.hasMatch(value) ? 'zh' : 'en': value,
        };
      }
    }
  }

  @override
  void visitMapLiteralEntry(MapLiteralEntry node) {
    if (path.endsWith('/mimo_voice_presets.dart') ||
        path.endsWith('/openai_voice_presets.dart')) {
      final key = literal(node.key), value = literal(node.value);
      if (key != null && value != null && chinese.hasMatch(key)) {
        add(key);
        add(value);
      }
    }
    super.visitMapLiteralEntry(node);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    if (path.endsWith('/ai_prompts.dart') && node.expression is StringLiteral) {
      final member = node.thisOrAncestorOfType<SwitchMember>();
      if (member != null) {
        final label = member is SwitchCase
            ? member.expression.toSource()
            : (member as SwitchPatternCase).guardedPattern.pattern.toSource();
        final id = label.split('.').last;
        final value = (node.expression as StringLiteral).stringValue!;
        entries['ai_${id}_prompt'] = {
          chinese.hasMatch(value) ? 'zh' : 'en': value
        };
      }
    }
    super.visitReturnStatement(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final parent = node.parent;
    if (path.endsWith('/ai_reading_skills.dart') ||
        path.endsWith('/appearance.dart')) {
      // UI literals only, not keys, variables, user data, or diagnostic messages.
      final named = parent is NamedExpression ? parent.name.label.name : null;
      final invocation = parent is ArgumentList ? parent.parent : null;
      final isText = invocation is InstanceCreationExpression &&
              invocation.constructorName.type.name2.lexeme == 'Text' ||
          invocation is MethodInvocation &&
              ['Text', '_hint'].contains(invocation.methodName.name);
      if (isText ||
          ['labelText', 'hintText', 'tooltip', 'name', 'description']
              .contains(named)) add(node.value);
    }
    super.visitSimpleStringLiteral(node);
  }
}

class Wire extends RecursiveAstVisitor<void> {
  Wire(this.path);
  final String path;
  final edits = <(int, int, String)>[];
  final removedConsts = <int>{};
  void replace(AstNode node, String value) {
    edits.add((node.offset, node.end, value));
    for (var ancestor = node.parent;
        ancestor != null;
        ancestor = ancestor.parent) {
      if (ancestor is InstanceCreationExpression &&
          ancestor.keyword?.lexeme == 'const') {
        final token = ancestor.keyword!;
        if (removedConsts.add(token.offset))
          edits.add((token.offset, token.end, ''));
      }
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final args = node.argumentList.arguments;
    if (['t', '_t', '_text', '_label', 'dictionaryLabel']
            .contains(node.methodName.name) &&
        args.length >= 2 &&
        args[args.length - 2] is StringLiteral &&
        args.last is StringLiteral) {
      final first = args[args.length - 2] as StringLiteral,
          last = args.last as StringLiteral;
      if (first.stringValue != null &&
          last.stringValue != null &&
          chinese.hasMatch(first.stringValue!)) {
        replace(node,
            'ModuStrings.text(${args.length == 3 ? args.first.toSource() : 'context'}, ${first.toSource()}, ${last.toSource()})');
        return;
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    final yes = node.thenExpression, no = node.elseExpression;
    if (yes is StringLiteral &&
        no is StringLiteral &&
        yes.stringValue != null &&
        no.stringValue != null &&
        chinese.hasMatch(yes.stringValue!) &&
        no.stringValue!.isNotEmpty &&
        !chinese.hasMatch(no.stringValue!)) {
      final matches =
          RegExp(r'localeOf\((\w+)\)').firstMatch(node.condition.toSource());
      replace(node,
          'ModuStrings.text(${matches?.group(1) ?? 'context'}, ${yes.toSource()}, ${no.toSource()})');
      return;
    }
    super.visitConditionalExpression(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if ((path.endsWith('/ai_reading_skills.dart') ||
            path.endsWith('/appearance.dart')) &&
        chinese.hasMatch(node.value)) {
      final parent = node.parent;
      final named = parent is NamedExpression ? parent.name.label.name : null;
      final invocation = parent is ArgumentList ? parent.parent : null;
      final isText = invocation is InstanceCreationExpression &&
              invocation.constructorName.type.name2.lexeme == 'Text' ||
          invocation is MethodInvocation &&
              ['Text', '_hint'].contains(invocation.methodName.name);
      if (isText || ['labelText', 'hintText', 'tooltip'].contains(named)) {
        replace(node,
            'ModuStrings.text(context, ${node.toSource()}, ${node.toSource()})');
      }
    }
    super.visitSimpleStringLiteral(node);
  }
}

void main(List<String> args) {
  if (args.single == 'wire') {
    for (final file
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.contains('/generated/'))
        continue;
      if (!file.path.startsWith('lib/page/') &&
          !file.path.startsWith('lib/widgets/')) continue;
      var code = file.readAsStringSync();
      final visitor = Wire(file.path);
      parseString(content: code).unit.accept(visitor);
      if (visitor.edits.isEmpty) continue;
      var end = code.length;
      for (final (start, stop, value) in visitor.edits
        ..sort((a, b) => b.$1.compareTo(a.$1))) {
        if (stop > end) continue;
        code = code.replaceRange(start, stop, value);
        end = start;
      }
      if (!code
          .contains("import 'package:anx_reader/l10n/modu_strings.dart';")) {
        code = "import 'package:anx_reader/l10n/modu_strings.dart';\n$code";
      }
      file.writeAsStringSync(code);
      stdout.writeln('${file.path}: ${visitor.edits.length}');
    }
    return;
  }
  if (args.single == 'extract') {
    final existing = File('lib/l10n/modu_source.json');
    if (existing.existsSync()) {
      final previous =
          jsonDecode(existing.readAsStringSync()) as Map<String, dynamic>;
      entries.addAll(previous
          .map((key, value) => MapEntry(key, Map<String, String>.from(value))));
    }
    for (final file
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.contains('/generated/'))
        continue;
      if (!file.path.startsWith('lib/page/') &&
          !file.path.startsWith('lib/widgets/') &&
          !file.path.endsWith('/readany_skills.dart') &&
          !file.path.endsWith('/ai_prompts.dart') &&
          !file.path.endsWith('/selection_toolbar.dart') &&
          !file.path.endsWith('/custom_css_profile.dart') &&
          !file.path.endsWith('/mimo_voice_presets.dart') &&
          !file.path.endsWith('/openai_voice_presets.dart') &&
          !file.path.startsWith('lib/service/translate/')) continue;
      parseString(content: file.readAsStringSync())
          .unit
          .accept(Extract(file.path));
    }
    add('跟随系统', 'Follow system');
    add('界面与内置提示词使用所选语言，用户自定义的提示词保持不变。',
        'The interface and built-in prompts use this language. Custom prompts remain unchanged.');
    add('确认删除此技能吗？', 'Delete this skill?');
    add('请填写技能名称和提示词', 'Enter a skill name and prompt');
    add('提示词不能为空', 'The prompt cannot be empty');
    add('提示词不能超过 4000 个字符', 'Prompts cannot exceed 4,000 characters');
    add('划词 AI', 'Selection AI');
    add('收起技能标签', 'Hide skill shortcuts');
    add('展开技能标签', 'Show skill shortcuts');
    add('上一段', 'Previous passage');
    add('下一段', 'Next passage');
    add('上一句', 'Previous sentence');
    add('下一句', 'Next sentence');
    final sorted = Map.fromEntries(
        entries.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    File('lib/l10n/modu_source.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(sorted)}\n');
    stdout.writeln(
        '${entries.length} strings, ${entries.values.where((e) => !e.containsKey('en')).length} need English');
    return;
  }
  final source =
      jsonDecode(File('lib/l10n/modu_source.json').readAsStringSync())
          as Map<String, dynamic>;
  final catalogs = <String, Map<String, dynamic>>{};
  for (final file
      in Directory('lib/l10n/catalogs').listSync().whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    final locale = file.uri.pathSegments.last.replaceFirst('.json', '');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    if (source.keys.any((key) =>
        data[key] is! String || (data[key] as String).trim().isEmpty)) {
      throw StateError('Incomplete translation: $locale');
    }
    for (final key in source.keys) {
      final original = source[key]['en'] ?? source[key]['zh'];
      final tokens = RegExp(r'\{\{?[a-zA-Z_]+\}\}?|`[^`]+`');
      final before =
          tokens.allMatches(original as String).map((m) => m[0]).toSet();
      final after =
          tokens.allMatches(data[key] as String).map((m) => m[0]).toSet();
      if (!after.containsAll(before))
        throw StateError(
            'Lost placeholder/code in $locale:$key $before -> $after');
    }
    catalogs[locale] = data;
  }
  if (catalogs.length != 15)
    throw StateError('Expected 15 catalogs: ${catalogs.keys}');
  String dartString(String value) => jsonEncode(value).replaceAll(r'$', r'\$');
  final output = StringBuffer(
      '// Generated by scripts/localization/catalog.dart generate.\n\n');
  output.writeln('const moduCatalogs = <String, Map<String, String>>{');
  for (final locale in catalogs.keys.toList()..sort()) {
    output.writeln('  ${dartString(locale)}: {');
    for (final key in source.keys) {
      output.writeln(
          '    ${dartString(key)}: ${dartString(catalogs[locale]![key] as String)},');
    }
    output.writeln('  },');
  }
  output.writeln('};\n\nconst moduSourceKeys = <String, String>{');
  for (final key in source.keys.where((key) => key.startsWith('ui_'))) {
    output.writeln(
        '  ${dartString(source[key]['zh'] as String)}: ${dartString(key)},');
  }
  output.writeln('};');
  File('lib/l10n/modu_catalogs.g.dart').writeAsStringSync(output.toString());
  stdout.writeln(
      'Generated ${catalogs.length} languages, ${source.length} keys each');
}
