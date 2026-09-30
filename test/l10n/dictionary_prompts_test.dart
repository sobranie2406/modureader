import 'dart:ui';
import 'package:anx_reader/l10n/modu_catalogs.g.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final skill = readAnySkills.singleWhere((s) => s.id == 'ai_dictionary');
  final selection = SelectionToolbarConfig.templateItems
      .singleWhere((item) => item.id == 'custom-preset-dictionary');
  final legacy = <String, List<String>>{
    'zh-CN': [
      "请作为独立的 AI 词典，使用当前 AI 模型已有的语言与百科知识，解释用户选中的词语或短语。不以本书知识库为依据，不分析当前书籍或章节，不生成“本段词汇网”。直接从词条开始回答，不输出获取上下文、书名或章节的开场说明。\n\n英文词语：\n1. 词条与音标：给出 IPA 国际音标；英式和美式不同则分别列出，标明词性。\n2. 中文翻译：列出最常见的中文对应词，多义词按常用义项区分。\n3. 中英文解释：每个主要义项给出中文释义与简洁的英文 definition。\n4. 用法：给出 1–2 个英文例句及中文翻译，必要时补充常用搭配。\n\n中文词语：\n1. 词条与拼音：使用带声调的拼音；多音字或不同读法分开说明，不擅自确定缺少语境的读音。\n2. 词语解释：用现代汉语说明常见含义，标注古义、成语义或专业义，不假设书中含义。\n3. 用法：给出简短例句；词源或典故只有可靠时才补充。\n\n相关词语知识（中英文均提供）：\n- 挑选 2–4 个确实相关的近义词、反义词、易混词或派生词，分别给出简短释义，并说明与所选词语的关系或区别；不存在合适条目时不要凑数。\n- 补充常用搭配、使用场景；词源、典故、专业背景等仅在有助于理解且有把握时简述。\n- 英文相关词附中文含义；中文相关词如有生僻字或多音字，补充带声调的拼音。不扩展为与词语无关的书籍分析。\n\n中英混合输入分别解释；长句先选取关键生词，不把整句硬当成一个词。没有把握的音标、拼音、释义和相关知识应明确说明，不能编造。优先使用模型已有知识；不足时由应用联网搜索在线词典／百科，再根据返回的真实资料整理答案。未收到检索资料前不要声称“已查询知识库”或“网上查到”，不捏造权威来源。保持简明，避免重复说明知识来源。\n",
      "解释所选词语 {selection}。英文给出 IPA 音标、词性、中文翻译、中英文释义、例句与常用搭配；中文给出带声调的拼音、含义、用法和相关词语。优先用模型已有知识，不足时根据应用返回的词典／百科资料整理并注明来源。不使用本书知识库，不编造读音或词源。"
    ],
    'en': [
      "Act as an independent AI dictionary, using the current model's existing linguistic and encyclopedic knowledge to explain the user's selected word or phrase. Do not rely on this book's knowledge base, analyze the current book or chapter, or generate a \"Vocabulary network for this passage\". Start directly with the entry, without introductory remarks about retrieving context, the book title, or the chapter. Use the user's chosen language for the explanation while retaining the bilingual, IPA, and pinyin requirements below.\n\nEnglish words:\n1. Entry and pronunciation: provide IPA transcription, listing British and American pronunciations separately when they differ, and indicate the part of speech.\n2. Chinese translation: list the most common Chinese equivalents, distinguishing common senses of polysemous words.\n3. Chinese and English definitions: give a Chinese explanation and a concise English definition for each main sense.\n4. Usage: provide 1–2 English example sentences with Chinese translations, adding common collocations when helpful.\n\nChinese words:\n1. Entry and pinyin: use pinyin with tone marks; explain alternative readings separately, and do not arbitrarily choose a pronunciation without sufficient context.\n2. Meaning: explain common meanings in modern Chinese, marking archaic, idiomatic, or specialist senses without assuming the meaning in the book.\n3. Usage: give brief examples; add etymologies or allusions only when reliable.\n\nRelated-word knowledge (for both English and Chinese):\n- Choose 2–4 genuinely related synonyms, antonyms, easily confused words, or derivatives; briefly define each and explain its relationship to or difference from the selected word. Do not pad the list when suitable entries are unavailable.\n- Add common collocations and usage contexts; briefly mention etymology, allusions, or specialist background only when useful and reliable.\n- Include Chinese meanings for related English words; add tone-marked pinyin for rare characters or characters with multiple readings in related Chinese words. Do not expand into unrelated book analysis.\n\nExplain mixed Chinese/English input separately; for long sentences, select key unfamiliar words instead of treating the entire sentence as a single word. Clearly flag uncertain pronunciation, pinyin, definitions, or related knowledge; do not invent them. Prefer the model's existing knowledge; if insufficient, let the app search online dictionaries/encyclopedias, then compose the answer from the actual returned material. Before receiving search results, do not claim to have \"queried the knowledge base\" or \"found it online\", and do not fabricate authoritative sources. Keep the answer concise and avoid repeating explanations of its knowledge sources.\n",
      "Explain the selected word or phrase {selection} in the user's chosen language. For English, provide IPA pronunciation, part of speech, Chinese translations, Chinese and English definitions, examples, and common collocations; for Chinese, provide pinyin with tone marks, meaning, usage, and related words. Prefer the model's existing knowledge; if insufficient, use dictionary/encyclopedia material returned by the app and cite its sources. Do not use this book's knowledge base or invent pronunciations or etymologies."
    ],
  };
  for (final entry in legacy.entries) {
    test('old ${entry.key} defaults update without becoming user overrides',
        () {
      expect(skill.isDefaultPrompt(entry.value[0]), true);
      expect(skill.isDefaultPrompt('${entry.value[0]} Custom edit'), false);
      final old = selection.copyWith(prompt: entry.value[1], enabled: true);
      expect(old.toJson().containsKey('prompt'), false);
      expect(old.localizedPrompt(const Locale('zh', 'CN')),
          selection.localizedPrompt(const Locale('zh', 'CN')));
      final custom = old.copyWith(prompt: '${entry.value[1]} Custom edit');
      expect(custom.toJson()['prompt'], custom.prompt);
      expect(custom.localizedPrompt(const Locale('en')), custom.prompt);
    });
  }
  for (final entry in moduCatalogs.entries) {
    test('dictionary follow-up strings exist in ${entry.key}', () {
      expect(entry.value['ui_dictionary_web_follow_up'], isNotEmpty);
      expect(entry.value['ui_dictionary_web_confirm_command'], isNotEmpty);
      expect(
          ModuStrings.isDefault('skill_ai_dictionary_prompt',
              entry.value['skill_ai_dictionary_prompt']!, skill.defaultPrompt),
          true);
      expect(entry.value['selection_custom-preset-dictionary_prompt'],
          contains('{selection}'));
    });
  }
}
