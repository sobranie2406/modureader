import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/enums/lang_list.dart';
import 'package:modu_reader/main.dart';
import 'package:modu_reader/service/ai/prompt_generate.dart';
import 'package:modu_reader/service/ai/index.dart';
import 'package:modu_reader/service/config/config_item.dart';
import 'package:modu_reader/service/translate/index.dart';
import 'package:modu_reader/widgets/ai/ai_chat_stream.dart';
import 'package:modu_reader/providers/ai_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:modu_reader/service/ai/langchain_runner.dart';
import 'package:modu_reader/service/translate/translation_answer.dart';

class AiTranslateProvider extends TranslateServiceProvider {
  @override
  TranslateService get service => TranslateService.ai;

  @override
  String getLabel(BuildContext context) =>
      ModuStrings.text(context, 'AI 翻译', 'AI Translation');

  /// AI translation uses native language names (e.g., "简体中文", "English")
  /// instead of ISO codes for better prompt understanding.
  @override
  String mapLanguageCode(LangListEnum lang) => lang.nativeName;

  @override
  Widget translate(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
  }) {
    final prompt = isFullText
        ? generatePromptFullTextTranslate(
            text,
            mapLanguageCode(to),
            mapLanguageCode(from),
          )
        : generatePromptTranslate(
            text,
            mapLanguageCode(to),
            mapLanguageCode(from),
            contextText: contextText,
          );

    return ProviderScope(
        overrides: [
          aiChatProvider(AiChatScope.selection).overrideWith(AiChat.new),
        ],
        child: AiChatStream(
          scope: AiChatScope.selection,
          draftScreen: 'lookup.translation',
          inlineResults: true,
          embedded: true,
          showSkillControls: false,
          initialMessage: prompt.buildString(),
          initialSourceText: text,
          initialSourceContext: contextText,
          initialSkillId: 'selection_toolbar',
          initialSelectionRequest: true,
          newConversation: true,
          sendImmediate: true,
          serviceIdentifier: Prefs().translationAiService,
          responseFilter: translationAnswer,
        ));
  }

  @override
  Stream<String> translateStream(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
    CancelableLangchainRunner? requestRunner,
  }) async* {
    try {
      final payload = isFullText
          ? generatePromptFullTextTranslate(
              text,
              mapLanguageCode(to),
              mapLanguageCode(from),
            )
          : generatePromptTranslate(
              text,
              mapLanguageCode(to),
              mapLanguageCode(from),
              contextText: contextText,
            );

      final messages = payload.buildMessages();

      await for (final result in aiGenerateStream(
        messages,
        identifier: Prefs().translationAiService,
        regenerate: false,
        requestRunner: requestRunner,
      )) {
        yield translationAnswer(result);
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'tip',
        label: 'Tip',
        type: ConfigItemType.tip,
        defaultValue:
            L10n.of(navigatorKey.currentContext!).settingsTranslateAiTip,
      ),
    ];
  }
}
