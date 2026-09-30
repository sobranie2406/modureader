import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/providers/book_toc.dart';
import 'package:anx_reader/providers/chapter_content_bridge.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/home_ai_execution.dart';
import 'package:anx_reader/service/ai/dictionary_lookup.dart';
import 'package:anx_reader/service/ai/dictionary_confirmation.dart';
import 'package:anx_reader/service/ai/dictionary_web_search.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/coalesced_stream.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/service/ai/reading_skill_execution.dart';
import 'package:anx_reader/service/ai/reading_request_snapshot.dart';
import 'package:anx_reader/service/ai/skill_message_label.dart';
import 'package:anx_reader/service/ai/tools/repository/chapter_content_repository.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_retriever.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:langchain_core/chat_models.dart';

part 'ai_chat.g.dart';

enum AiChatScope {
  library,
  reader;

  String get storageKey => name;
}

@Riverpod(keepAlive: true)
class AiChat extends _$AiChat {
  String? _currentSessionId;
  ReadingRequestSnapshot? _lastReadingRequest;
  late final AiChatScope _scope;

  @override
  FutureOr<List<ChatMessage>> build(AiChatScope scope) async {
    _scope = scope;
    _currentSessionId = null;
    return List<ChatMessage>.empty();
  }

  Future<void> sendMessage(String message) async {
    state = AsyncData([
      ...state.whenOrNull(data: (data) => data) ?? [],
      ChatMessage.humanText(message),
    ]);
  }

  void restore(List<ChatMessage> history, {String? sessionId}) {
    if (sessionId != null) {
      _currentSessionId = sessionId;
    }
    state = AsyncData(history);
  }

  Stream<List<ChatMessage>> sendMessageStream(
    String message,
    WidgetRef widgetRef,
    bool isRegenerate, {
    String? skillId,
    String? sourceText,
    String? homePromptId,
    CancelableLangchainRunner? requestRunner,
  }) async* {
    final sessionId = _ensureSessionId();
    final selectedProvider =
        widgetRef.read(aiProvidersProvider.notifier).getSelectedProvider();
    final serviceId = selectedProvider?.id ?? Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final model = selectedProvider?.model.trim().isNotEmpty == true
        ? selectedProvider!.model.trim()
        : (config['model'])?.trim() ?? '';
    final historyNotifier = widgetRef.read(aiHistoryProvider.notifier);
    final initialHistoryState = widgetRef
        .read(aiHistoryProvider)
        .maybeWhen(data: (value) => value, orElse: () => const []);
    AiChatHistoryEntry? entry;
    for (final item in initialHistoryState) {
      if (item.id == sessionId) {
        entry = item;
        break;
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (isRegenerate) homePromptId ??= entry?.homePromptId;

    if (_scope == AiChatScope.reader &&
        !isRegenerate &&
        skillId == null &&
        isDictionaryWebConfirmation(message)) {
      final original = dictionarySelectionFromRequest(
          _lastReadingRequest ?? entry?.readingRequest);
      if (original == null) {
        throw StateError('无法找到这段对话原先查询的词语，请重新选词使用 AI 词典后，再输入“确认联网搜索”。');
      }
      skillId = aiDictionaryWebSkillId;
      sourceText = original;
    }

    final previousMessages = List<ChatMessage>.from(state.value ?? const []);
    if (isRegenerate) {
      final lastHuman =
          previousMessages.lastIndexWhere((m) => m is HumanChatMessage);
      if (lastHuman >= 0) {
        previousMessages.removeRange(lastHuman, previousMessages.length);
      }
    }
    final messages = <ChatMessage>[
      ...previousMessages,
      ChatMessage.humanText(message),
    ];
    final skillLabels = <int, String>{
      for (final label in (entry?.skillLabels ?? <int, String>{}).entries)
        if (label.key < previousMessages.length) label.key: label.value,
    };
    final skillLabel =
        (isRegenerate ? entry?.skillLabels[previousMessages.length] : null) ??
            skillMessageLabel(message, skillId: skillId);
    if (skillLabel != null) skillLabels[previousMessages.length] = skillLabel;

    ReadingSkillRequest? replay;
    if (isRegenerate && _scope == AiChatScope.reader) {
      final saved = _lastReadingRequest ?? entry?.readingRequest;
      if (saved == null) {
        throw StateError('这条旧对话没有保存原文范围，无法安全重试。请重新选择阅读技能发起请求。');
      }
      final reading = widgetRef.read(currentReadingProvider);
      replay = saved.replay(
          currentBookId: reading.book?.id,
          currentChapterHref: reading.chapterHref);
    }
    final skillPolicy = readingSkillPolicyFor(skillId);
    final skillRequest = replay ??
        (skillPolicy == null
            ? null
            : await _buildReadingSkillRequest(
                widgetRef,
                policy: skillPolicy,
                prompt: message,
                selectedText: sourceText,
              ));
    final homeRequest = skillRequest == null && _scope == AiChatScope.library
        ? buildHomeAiRequest(
            conversation: messages,
            promptId: homePromptId,
          )
        : null;
    final List<ChatMessage> requestMessages;
    if (skillRequest != null) {
      requestMessages = skillRequest.messages;
    } else if (homeRequest != null) {
      requestMessages = homeRequest.messages;
    } else {
      final knowledgeContext = await _loadKnowledgeContext(widgetRef, message);
      requestMessages = knowledgeContext == null
          ? messages
          : [ChatMessage.system(knowledgeContext), ...messages];
    }

    if (requestRunner?.isCancelled == true || _currentSessionId != sessionId)
      return;
    final reading = widgetRef.read(currentReadingProvider);
    final readingRequest = _scope == AiChatScope.reader
        ? (isRegenerate
            ? (_lastReadingRequest ?? entry?.readingRequest)
            : ReadingRequestSnapshot(
                skillId: skillPolicy?.id,
                bookId: reading.book?.id,
                chapterHref: reading.chapterHref,
                request: skillRequest ??
                    ReadingSkillRequest(
                        messages: requestMessages, useAgent: true),
              ))
        : null;

    List<ChatMessage> updatedMessages = [
      ...messages,
      ChatMessage.ai(''),
    ];

    final draftEntry = (entry ??
            AiChatHistoryEntry(
              id: sessionId,
              scope: _scope.storageKey,
              serviceId: serviceId,
              model: model,
              createdAt: entry?.createdAt ?? now,
              updatedAt: now,
              messages: List<ChatMessage>.from(updatedMessages),
              completed: false,
              homePromptId: homePromptId,
            ))
        .copyWith(
      messages: List<ChatMessage>.from(updatedMessages),
      updatedAt: now,
      completed: false,
      scope: _scope.storageKey,
      serviceId: serviceId,
      model: model,
      homePromptId: homePromptId,
      readingRequest: readingRequest,
      skillLabels: skillLabels,
    );

    await historyNotifier.upsert(draftEntry);
    if (requestRunner?.isCancelled == true || _currentSessionId != sessionId)
      return;
    _lastReadingRequest = readingRequest;
    state = AsyncData(updatedMessages);

    yield updatedMessages;
    if (requestRunner?.isCancelled == true || _currentSessionId != sessionId)
      return;

    String assistantResponse = "";
    var latestMessages = updatedMessages;
    try {
      // The provider closes its runner on completion. Keep that separate from
      // user cancellation so the final dictionary answer can still be saved.
      Stream<String> dictionaryGenerate(List<ChatMessage> input) async* {
        final child = CancelableLangchainRunner();
        final finished = Completer<void>();
        if (requestRunner != null) {
          unawaited(Future.any([requestRunner.whenCancelled, finished.future])
              .then((_) async {
            if (requestRunner.isCancelled) await child.cancel();
          }));
        }
        try {
          if (requestRunner?.isCancelled == true) return;
          yield* aiGenerateStream(
            input,
            identifier: serviceId,
            providerOverride: selectedProvider,
            regenerate: isRegenerate,
            useAgent: false,
            ref: widgetRef,
            requestRunner: child,
          );
        } finally {
          finished.complete();
          await child.cancel();
        }
      }

      final responseStream = readingRequest?.skillId == aiDictionaryWebSkillId
          ? dictionaryWebLookup(
              messages: requestMessages,
              generate: dictionaryGenerate,
              search: (term) => DictionaryWebSearch()
                  .search(term, cancelled: requestRunner?.whenCancelled),
              isCancelled: () => requestRunner?.isCancelled == true,
            )
          : readingRequest?.skillId == aiDictionarySkillId
              ? dictionaryLookup(
                  messages: requestMessages,
                  generate: dictionaryGenerate,
                  isCancelled: () => requestRunner?.isCancelled == true,
                )
              : aiGenerateStream(
                  requestMessages,
                  regenerate: isRegenerate,
                  useAgent:
                      skillRequest?.useAgent ?? homeRequest?.useAgent ?? true,
                  allowedToolIds: skillRequest?.allowedToolIds ??
                      homeRequest?.allowedToolIds,
                  ref: widgetRef,
                  requestRunner: requestRunner,
                );
      await for (final chunk in coalesceSnapshots(responseStream)) {
        // A fresh selection may start while an old provider is still closing.
        // Its late output must not replace the new conversation or its history.
        if (requestRunner?.isCancelled == true ||
            _currentSessionId != sessionId) return;
        assistantResponse = chunk;

        final updatedMessagesWithResponse =
            List<ChatMessage>.from(updatedMessages);
        updatedMessagesWithResponse[updatedMessagesWithResponse.length - 1] =
            assistantMessageFromDisplayContent(assistantResponse);

        latestMessages = updatedMessagesWithResponse;
        state = AsyncData(updatedMessagesWithResponse);
        yield updatedMessagesWithResponse;
      }
      if (requestRunner?.isCancelled == true || _currentSessionId != sessionId)
        return;
      final completedEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(latestMessages),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: true,
        model: model,
      );
      await historyNotifier.upsert(completedEntry);
    } catch (_) {
      if (_currentSessionId != sessionId) return;
      final failedEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(latestMessages),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: false,
        model: model,
      );
      await historyNotifier.upsert(failedEntry);
      rethrow;
    }
  }

  Future<ReadingSkillRequest> _buildReadingSkillRequest(
    WidgetRef ref, {
    required ReadingSkillExecutionPolicy policy,
    required String prompt,
    String? selectedText,
  }) async {
    final reading = ref.read(currentReadingProvider);
    final normalizedSelection = selectedText?.trim();
    late final _ReadingSkillSource source;

    switch (policy.scope) {
      case ReadingSkillSourceScope.dictionarySelection:
        if (normalizedSelection == null || normalizedSelection.isEmpty) {
          throw StateError('请先选择需要查询的词语，再使用“AI 词典解释”。');
        }
        source = _ReadingSkillSource(
          description: '待解释的选中词语（不使用本书知识库）',
          content: normalizedSelection,
        );
        break;
      case ReadingSkillSourceScope.currentChapter:
        source = _ReadingSkillSource(
          description: '当前章节正文',
          content: await _requireCurrentChapter(ref),
        );
        break;
      case ReadingSkillSourceScope.selectionOrCurrentChapter:
        if (normalizedSelection != null && normalizedSelection.isNotEmpty) {
          source = _ReadingSkillSource(
            description: '用户在当前章节中选中的原文',
            content: normalizedSelection,
          );
        } else {
          source = _ReadingSkillSource(
            description: '当前章节正文（用户未选择具体文本）',
            content: await _requireCurrentChapter(ref),
          );
        }
        break;
      case ReadingSkillSourceScope.selectionRequired:
        if (normalizedSelection == null || normalizedSelection.isEmpty) {
          throw StateError(policy.id == selectionToolbarSkillId
              ? '请先在阅读界面选择需要处理的文字。'
              : '请先在阅读界面选择需要翻译的原文，再使用“智能翻译”。');
        }
        source = _ReadingSkillSource(
          description: '用户在当前章节中选中的原文',
          content: normalizedSelection,
        );
        break;
      case ReadingSkillSourceScope.throughCurrentPosition:
        source = _ReadingSkillSource(
          description: '从全书开头到当前阅读位置的进度内原文',
          content: await _buildBookCoverage(
            ref,
            throughCurrentPosition: true,
          ),
        );
        break;
      case ReadingSkillSourceScope.wholeBook:
        source = _ReadingSkillSource(
          description: '按目录覆盖全书的章节代表性原文',
          content: await _buildBookCoverage(
            ref,
            throughCurrentPosition: false,
          ),
        );
        break;
    }

    final allowedTools = policy.allowedToolIds;
    final agentAvailable = allowedTools == null ||
        allowedTools.any(Prefs().enabledAiToolIds.contains);
    final request = buildReadingSkillRequest(
      policy: policy,
      prompt: prompt,
      sourceContent: source.content,
      sourceDescription: source.description,
      bookTitle: reading.book?.title,
      chapterTitle: reading.chapterTitle,
      chapterHref: reading.chapterHref,
      responseLanguage: Prefs().effectiveLocale.toLanguageTag(),
      agentAvailable: agentAvailable,
    );
    AnxLog.info(
      'AI reading skill ${policy.id}: scope=${policy.scope.name}, '
      'sourceCharacters=${source.content.length}, '
      'agent=${request.useAgent}, tools=${request.allowedToolIds ?? const {}}',
    );
    return request;
  }

  Future<String> _requireCurrentChapter(WidgetRef ref) async {
    final content = await const ChapterContentRepository().fetchCurrent(ref);
    if (content.trim().isEmpty) {
      throw StateError('当前章节正文为空，请等待阅读页面加载完成后重试。');
    }
    return content;
  }

  Future<String> _buildBookCoverage(
    WidgetRef ref, {
    required bool throughCurrentPosition,
  }) async {
    final reading = ref.read(currentReadingProvider);
    final book = reading.book;
    if (!reading.isReading || book == null) {
      throw StateError('当前没有正在阅读的书籍。');
    }

    var chapters = _flattenUniqueChapters(ref.read(bookTocProvider));
    if (chapters.isEmpty) {
      throw StateError('书籍目录尚未加载，无法确定需要处理的章节范围。');
    }

    if (throughCurrentPosition) {
      final currentIndex = _currentChapterIndex(chapters, reading.chapterHref,
          reading.percentage ?? book.readingPercentage);
      if (currentIndex < 0) {
        throw StateError('无法在目录中定位当前章节，为避免剧透已停止人物追踪。');
      }
      chapters = chapters.take(currentIndex + 1).toList(growable: false);
    }

    KnowledgeIndexSnapshot? snapshot;
    if (book.id > 0) {
      try {
        snapshot = await BookKnowledgeIndexService().loadSnapshot(book);
      } catch (_) {
        AnxLog.warning('Reading skill index unavailable; using reader source');
      }
    }

    final indexedByChapter = <String, List<KnowledgeChunk>>{};
    for (final chunk in snapshot?.chunks ?? const <KnowledgeChunk>[]) {
      indexedByChapter.putIfAbsent(chunk.chapterId, () => []).add(chunk);
    }

    final handlers = ref.read(chapterContentBridgeProvider);
    final repository = const ChapterContentRepository();
    const totalCharacterBudget = 48000;
    var remainingBudget = totalCharacterBudget;
    final output = StringBuffer();
    output.writeln('目录范围：');
    for (var index = 0; index < chapters.length; index++) {
      output.writeln('${index + 1}. ${chapters[index].label}');
    }
    output.writeln('\n章节原文：');

    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      final remainingChapters = chapters.length - index;
      final chapterBudget =
          (remainingBudget ~/ remainingChapters).clamp(300, 8000);
      String content;

      final isCurrentChapter = throughCurrentPosition &&
          index == chapters.length - 1 &&
          _sameHref(chapter.href, reading.chapterHref);
      if (isCurrentChapter) {
        if (handlers == null) {
          throw StateError('阅读器尚未就绪，无法确定已读范围，请稍后重试。');
        }
        content = await handlers.fetchPreviousContent(
          maxCharacters: chapterBudget * 3,
        );
      } else {
        final indexed = indexedByChapter[chapter.id];
        if (indexed != null && indexed.isNotEmpty) {
          content = indexed.map((chunk) => chunk.text).join('\n');
        } else {
          content = await repository.fetchByHref(
            ref,
            href: chapter.href,
          );
        }
      }

      final excerpt = _balancedExcerpt(content, chapterBudget);
      if (excerpt.isEmpty) continue;
      output
        ..writeln('\n<chapter>')
        ..writeln('章节名：${chapter.label}')
        ..writeln('章节位置：${chapter.href}')
        ..writeln(excerpt)
        ..writeln('</chapter>');
      remainingBudget -= excerpt.length;
      if (remainingBudget <= 0) break;
    }

    final result = output.toString().trim();
    if (!result.contains('<chapter>')) {
      throw StateError('未能提取指定范围内的书籍正文。');
    }
    return result;
  }

  List<TocItem> _flattenUniqueChapters(List<TocItem> roots) {
    final chapters = <TocItem>[];
    final seenHrefs = <String>{};

    void visit(TocItem item) {
      final href = _normalizedHref(item.href);
      if (href.isNotEmpty && seenHrefs.add(href)) chapters.add(item);
      for (final child in item.subitems) {
        visit(child);
      }
    }

    for (final root in roots) {
      visit(root);
    }
    return chapters;
  }

  int _currentChapterIndex(
    List<TocItem> chapters,
    String? currentHref,
    double currentPercentage,
  ) {
    final exact = chapters.indexWhere(
      (chapter) => _sameHref(chapter.href, currentHref),
    );
    if (exact >= 0) return exact;

    var candidate = -1;
    for (var index = 0; index < chapters.length; index++) {
      if (chapters[index].startPercentage <= currentPercentage) {
        candidate = index;
      } else {
        break;
      }
    }
    return candidate;
  }

  bool _sameHref(String left, String? right) =>
      _normalizedHref(left) == _normalizedHref(right ?? '');

  String _normalizedHref(String href) => href.trim().split('#').first;

  String _balancedExcerpt(String content, int limit) {
    final normalized = content.trim();
    if (normalized.isEmpty || limit <= 0) return '';
    if (normalized.length <= limit) return normalized;

    const marker = '\n…〔本章中间内容已按模型上下文预算压缩〕…\n';
    final available = limit - marker.length * 2;
    if (available < 90) return normalized.substring(0, limit);
    final part = available ~/ 3;
    final middleStart = (normalized.length - part) ~/ 2;
    return '${normalized.substring(0, part)}$marker'
        '${normalized.substring(middleStart, middleStart + part)}$marker'
        '${normalized.substring(normalized.length - part)}';
  }

  Future<String?> _loadKnowledgeContext(WidgetRef ref, String query) async {
    final reading = ref.read(currentReadingProvider);
    final book = reading.book;
    if (_scope != AiChatScope.reader ||
        !reading.isReading ||
        book == null ||
        book.id <= 0 ||
        query.trim().isEmpty) {
      return null;
    }

    return knowledgeContextFor(
        await BookKnowledgeRetriever().search(book, query));
  }

  void clear() {
    state = AsyncData(List<ChatMessage>.empty());
    _currentSessionId = null;
    _lastReadingRequest = null;
  }

  void loadHistoryEntry(AiChatHistoryEntry entry) {
    _currentSessionId = entry.id;
    _lastReadingRequest = entry.readingRequest;
    state = AsyncData(List<ChatMessage>.from(entry.messages));
  }

  String? get currentSessionId => _currentSessionId;
  String? get currentDictionarySelection =>
      dictionarySelectionFromRequest(_lastReadingRequest);

  String _ensureSessionId() {
    return _currentSessionId ??= _generateSessionId();
  }

  String _generateSessionId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }
}

class _ReadingSkillSource {
  const _ReadingSkillSource({
    required this.description,
    required this.content,
  });

  final String description;
  final String content;
}
