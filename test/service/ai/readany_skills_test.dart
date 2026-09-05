import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/settings_page/ai_reading_skills.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/reading_skill_prompt_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('contains the complete ReadAny built-in skill catalog', () {
    expect(readAnySkills, hasLength(10));
    expect(
      readAnySkills.map((skill) => skill.id).toSet(),
      {
        'smart_summary',
        'book_summary',
        'concept_explainer',
        'argument_analyzer',
        'character_tracker',
        'quote_collector',
        'reading_guide',
        'smart_translator',
        'vocabulary_helper',
        'mindmap',
      },
    );
  });

  test('each ReadAny skill has user-facing content and an AI prompt', () {
    for (final skill in readAnySkills) {
      expect(skill.name.trim(), isNotEmpty);
      expect(
        RegExp(r'[A-Za-z]').hasMatch(skill.name),
        isFalse,
        reason: '${skill.id} 的界面名称应全部使用中文',
      );
      expect(skill.description.trim(), isNotEmpty);
      expect(skill.defaultPrompt.trim(), isNotEmpty);
    }
  });

  test('built-in prompts are purpose-specific and evidence-aware', () {
    final promptsById = {
      for (final skill in readAnySkills) skill.id: skill.defaultPrompt.trim(),
    };

    expect(promptsById.values.toSet(), hasLength(readAnySkills.length));
    for (final entry in promptsById.entries) {
      expect(
        entry.value.length,
        greaterThan(220),
        reason: '${entry.key} 需要有足够的任务边界和输出结构',
      );
    }

    final requiredTerms = <String, List<String>>{
      'smart_summary': ['当前章节', '文学/叙事', '非虚构/论述', '不要杜撰'],
      'book_summary': ['全书结构', '实际覆盖范围', '不杜撰', '最终结局'],
      'concept_explainer': ['一句话定义', '文中含义', '易混点', '不要猜测'],
      'argument_analyzer': ['论证链', '证据清单', '隐含假设', '最强反方'],
      'character_tracker': ['阅读进度', '关系网', '文本事实', '合理推断'],
      'quote_collector': ['逐字保留', '原文引用', '绝对不得', '位置'],
      'reading_guide': ['阅读目标', '边读边问', '阅读后自检', '不剧透'],
      'smart_translator': ['前后文', '术语', '完整译文', '翻译说明'],
      'vocabulary_helper': ['本文语境义', '常见义对比', '新例句', '词汇网'],
      'mindmap': ['mindmap_draw', '4–7 个一级分支', '节点 ID', '不要自行补全'],
    };

    for (final entry in requiredTerms.entries) {
      final prompt = promptsById[entry.key]!;
      for (final term in entry.value) {
        expect(prompt, contains(term), reason: '${entry.key} 应覆盖：$term');
      }
    }
  });

  test('custom built-in prompt overrides and resets independently', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final skill = readAnySkills.firstWhere(
      (item) => item.id == 'concept_explainer',
    );

    ReadingSkillPromptStore.save(skill, '自定义概念提示词');
    expect(ReadingSkillPromptStore.promptFor(skill), '自定义概念提示词');

    ReadingSkillPromptStore.reset(skill);
    expect(ReadingSkillPromptStore.promptFor(skill), skill.defaultPrompt);
  });

  testWidgets('AI reading skills settings exposes toggles and prompt editor',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AiReadingSkillsSettings()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsNWidgets(10));
    expect(find.text('本章总结'), findsOneWidget);
    expect(find.text('全书总结'), findsOneWidget);
    expect(find.text('词汇助手'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('reading-skill-switch-vocabulary_helper')),
    );
    await tester.pumpAndSettle();

    expect(Prefs().isReadAnySkillEnabled('vocabulary_helper'), isFalse);

    await tester.tap(
      find.byKey(const ValueKey('reading-skill-concept_explainer')),
    );
    await tester.pumpAndSettle();
    expect(find.text('概念解析·提示词'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reading-skill-prompt-editor')),
      findsOneWidget,
    );
    expect(find.text('恢复默认'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });
}
