import 'dart:async';
import 'package:anx_reader/service/ai/answer_presentation.dart';
import 'package:anx_reader/widgets/ai/ai_chat_scroll_controller.dart';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/widgets/ai/ai_provider_logo.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/skill_message_label.dart';
import 'package:anx_reader/service/ai/dictionary_confirmation.dart';
import 'package:anx_reader/service/ai/home_ai_execution.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/model_picker_dialog.dart';
import 'package:anx_reader/widgets/ai/tool_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/apply_book_tags_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/mindmap_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/organize_bookshelf_step_tile.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/delete_confirm.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:langchain_core/chat_models.dart';

import 'package:anx_reader/models/ai_quick_prompt_chip.dart';

class _HomeStarterPrompt {
  const _HomeStarterPrompt(this.id, this.text);

  final String id;
  final String text;
}

class AiChatStream extends ConsumerStatefulWidget {
  const AiChatStream({
    super.key,
    this.initialMessage,
    this.initialSourceText,
    this.initialSkillId,
    this.newConversation = false,
    this.sendImmediate = false,
    this.quickPromptChips = const [],
    this.trailing,
    this.scope = AiChatScope.library,
  });

  final String? initialMessage;
  final String? initialSourceText;
  final String? initialSkillId;
  final bool newConversation;
  final bool sendImmediate;
  final List<AiQuickPromptChip> quickPromptChips;
  final List<Widget>? trailing;
  final AiChatScope scope;

  @override
  ConsumerState<AiChatStream> createState() => AiChatStreamState();
}

class AiChatStreamState extends ConsumerState<AiChatStream> {
  final TextEditingController inputController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Stream<List<ChatMessage>>? _messageStream;
  StreamController<List<ChatMessage>>? _messageController;
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  final AiChatScrollController _scrollController = AiChatScrollController();
  GlobalKey _replyStartKey = GlobalKey(debugLabel: 'ai-reply-start');
  final FocusNode _inputFocusNode = FocusNode();
  bool _isStreaming = false;
  bool _showSkillPrompts = false;
  double _fontSize = 14.0;
  String? _readerSourceText;
  String? _lastSubmittedSkillId;
  String? _lastSubmittedSourceText;
  String? _lastSubmittedHomePromptId;
  CancelableLangchainRunner? _requestRunner;

  List<Map<String, String>> _getQuickPrompts(BuildContext context) {
    return [
      {
        'label': L10n.of(context).aiQuickPromptExplain,
        'prompt': L10n.of(context).aiQuickPromptExplainText,
      },
      {
        'label': L10n.of(context).aiQuickPromptOpinion,
        'prompt': L10n.of(context).aiQuickPromptOpinionText,
      },
      {
        'label': L10n.of(context).aiQuickPromptSummary,
        'prompt': L10n.of(context).aiQuickPromptSummaryText,
      },
      {
        'label': L10n.of(context).aiQuickPromptAnalyze,
        'prompt': L10n.of(context).aiQuickPromptAnalyzeText,
      },
      {
        'label': L10n.of(context).aiQuickPromptSuggest,
        'prompt': L10n.of(context).aiQuickPromptSuggestText,
      },
    ];
  }

  List<_HomeStarterPrompt> _getStarterPrompts(BuildContext context) {
    final l10n = L10n.of(context);
    return [
      _HomeStarterPrompt(homePromptRecentBooks, l10n.quickPrompt1),
      _HomeStarterPrompt(homePromptLatestSession, l10n.quickPrompt2),
      _HomeStarterPrompt(homePromptHighestProgress, l10n.quickPrompt3),
      _HomeStarterPrompt(homePromptYesterdayNotes, l10n.quickPrompt4),
      _HomeStarterPrompt(homePromptUnreadBooks, l10n.quickPrompt5),
      _HomeStarterPrompt(homePromptRecommendRecent, l10n.quickPrompt6),
      _HomeStarterPrompt(homePromptTodayHighlights, l10n.quickPrompt7),
      _HomeStarterPrompt(homePromptWeeklyReadingTime, l10n.quickPrompt8),
      _HomeStarterPrompt(homePromptNoteQuote, l10n.quickPrompt9),
      _HomeStarterPrompt(homePromptReadNext, l10n.quickPrompt10),
      _HomeStarterPrompt(homePromptOrganizeByGenre, l10n.quickPrompt11),
      _HomeStarterPrompt(homePromptOrganizeByProgress, l10n.quickPrompt12),
    ];
  }

  @override
  void initState() {
    super.initState();
    _fontSize = Prefs().aiChatFontSize;
    inputController.text = widget.initialMessage ?? '';
    _readerSourceText =
        _normalizeSourceText(widget.initialSourceText ?? widget.initialMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.newConversation) _resetConversation();
      if (widget.sendImmediate) {
        _sendMessage(
            skillId: widget.initialSkillId, sourceText: _readerSourceText);
      }
    });
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(covariant AiChatStream oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMessage != widget.initialMessage ||
        oldWidget.initialSourceText != widget.initialSourceText) {
      _readerSourceText = _normalizeSourceText(
          widget.initialSourceText ?? widget.initialMessage);
      inputController.text = widget.initialMessage ?? '';
    }
  }

  String? _normalizeSourceText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void setReaderSourceText(String? value) {
    final normalized = _normalizeSourceText(value);
    _readerSourceText = normalized;
    if (normalized != null) {
      inputController.text = normalized;
    }
  }

  void _resetConversation() {
    _cancelStreaming();
    _scrollController.stopFollowing();
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _messageController?.close();
    _messageController = null;
    ref.read(aiChatProvider(widget.scope).notifier).clear();
    setState(() {
      _messageStream = null;
      _lastSubmittedSkillId = null;
      _lastSubmittedSourceText = null;
      _lastSubmittedHomePromptId = null;
      _showSkillPrompts = false;
    });
  }

  /// Also works when the existing split panel keeps this State alive.
  void beginSelectionQuestion(
      {required String message,
      required String sourceText,
      String? skillId,
      bool sendImmediate = true}) {
    _resetConversation();
    _readerSourceText = _normalizeSourceText(sourceText);
    inputController.text = message;
    if (sendImmediate)
      _sendMessage(skillId: skillId, sourceText: _readerSourceText);
  }

  @override
  void dispose() {
    _requestRunner?.cancel();
    inputController.dispose();
    _messageSubscription?.cancel();
    _messageController?.close();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  AiProvider? _currentProvider(List<AiProvider> enabledProviders) {
    final selectedId = Prefs().selectedAiService;
    try {
      return enabledProviders.firstWhere((p) => p.id == selectedId);
    } catch (_) {
      return enabledProviders.isNotEmpty ? enabledProviders.first : null;
    }
  }

  String _modelLabel(AiProvider provider) {
    final model = provider.model;
    if (model.trim().isNotEmpty) return model;
    // Fallback: look up default model from built-in templates
    final defaults = buildDefaultAiServices();
    for (final d in defaults) {
      if (d.identifier == provider.id) return d.defaultModel;
    }
    return '';
  }

  void _onProviderSelected(String providerId) {
    if (_isStreaming) return;
    ref.read(aiProvidersProvider.notifier).setSelectedProvider(providerId);
  }

  AiProvider? _providerById(List<AiProvider> providers, String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _scrollToBottom({bool force = true}) {
    _scrollController.followAfterLayout(force: force);
  }

  Widget _buildHistoryDrawer(BuildContext context) {
    final historyState = ref.watch(aiHistoryProvider);
    return SafeArea(
      child: Column(
        children: [
          ListTile(
            title: Text(L10n.of(context).conversationHistory),
            trailing: DeleteConfirm(
              delete: () => _confirmClearHistory(context),
              deleteIcon: Icon(Icons.delete_sweep),
            ),
          ),
          Expanded(
            child: historyState.when(
              data: (items) {
                final scopedItems = items
                    .where((entry) => entry.scope == widget.scope.storageKey)
                    .toList(growable: false);
                if (scopedItems.isEmpty) {
                  return Center(
                    child: Text(L10n.of(context).noConversationTip),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: scopedItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final entry = scopedItems[index];
                    return _buildHistoryTile(context, entry);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Text(L10n.of(context).failedToLoadHistoryTip),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(BuildContext context, AiChatHistoryEntry entry) {
    final allProviders = ref.watch(aiProvidersProvider);
    final provider = _providerById(allProviders, entry.serviceId);
    final statusColor =
        entry.completed ? Colors.green : Theme.of(context).colorScheme.tertiary;
    final title = _deriveTitle(entry);
    final subtitle = _buildHistorySubtitle(provider, entry);

    return FilledContainer(
      margin: EdgeInsets.symmetric(horizontal: 8),
      padding: EdgeInsets.all(8),
      radius: 15,
      child: GestureDetector(
        onTap: () => _handleHistoryTap(context, entry),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      _formatTimestamp(entry.updatedAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                Spacer(),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.circle, size: 10, color: statusColor),
                    DeleteConfirm(
                        delete: () => _confirmDeleteHistory(context, entry)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildHistorySubtitle(AiProvider? provider, AiChatHistoryEntry entry) {
    final serviceLabel = provider?.title ?? entry.serviceId;
    if (entry.model.isEmpty) {
      return serviceLabel;
    }
    return '$serviceLabel · ${entry.model}';
  }

  Widget? _providerLogo(AiProvider? provider) {
    return provider == null
        ? null
        : AiProviderLogo(provider: provider, size: 20);
  }

  String _deriveTitle(AiChatHistoryEntry entry) {
    for (final message in entry.messages) {
      if (message is HumanChatMessage) {
        final content = message.contentAsString.trim();
        if (content.isNotEmpty) {
          final firstLine = content.split('\n').first.trim();
          return firstLine;
        }
      }
    }
    if (entry.messages.isNotEmpty) {
      return 'Conversation';
    }
    return 'Empty conversation';
  }

  String _formatTimestamp(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final date =
        '${dateTime.year}-${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)}';
    final time = '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
    return '$date $time';
  }

  Future<void> _handleHistoryTap(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    if (_isStreaming) {
      _cancelStreaming();
    }
    _messageSubscription?.cancel();
    _messageSubscription = null;
    final controller = _messageController;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    if (!mounted || !context.mounted) return;
    _messageController = null;

    ref.read(aiChatProvider(widget.scope).notifier).loadHistoryEntry(entry);

    setState(() {
      _readerSourceText = null;
      _lastSubmittedSkillId = null;
      _lastSubmittedSourceText = null;
      _lastSubmittedHomePromptId = entry.homePromptId;
      _messageStream = null;
      _showSkillPrompts = false;
      // reset state when switching service
    });

    Navigator.of(context).pop();
    _scrollToBottom();
  }

  Future<void> _confirmDeleteHistory(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    await ref.read(aiHistoryProvider.notifier).remove(entry.id);

    final currentSessionId =
        ref.read(aiChatProvider(widget.scope).notifier).currentSessionId;
    if (currentSessionId == entry.id) {
      ref.read(aiChatProvider(widget.scope).notifier).clear();
      setState(() {
        _lastSubmittedSkillId = null;
        _lastSubmittedSourceText = null;
        _lastSubmittedHomePromptId = null;
        _messageStream = null;
        // reset state when conversation changes
      });
    }
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    await ref
        .read(aiHistoryProvider.notifier)
        .clearScope(widget.scope.storageKey);
    ref.read(aiChatProvider(widget.scope).notifier).clear();
    setState(() {
      _lastSubmittedSkillId = null;
      _lastSubmittedSourceText = null;
      _lastSubmittedHomePromptId = null;
      _messageStream = null;
      _showSkillPrompts = false;
    });
  }

  void _sendMessage({
    bool isRegenerate = false,
    String? skillId,
    String? sourceText,
    String? homePromptId,
  }) {
    if (_isStreaming) {
      return;
    }

    if (inputController.text.trim().isEmpty) return;
    final message = inputController.text.trim();
    // Reader requests are independent tasks. Clearing starts a fresh session
    // without deleting saved history; regenerate still replays the same task.
    final confirmingDictionarySearch =
        skillId == null && isDictionaryWebConfirmation(message);
    if (widget.scope == AiChatScope.reader &&
        !isRegenerate &&
        !confirmingDictionarySearch) {
      ref.read(aiChatProvider(widget.scope).notifier).clear();
    }
    inputController.clear();
    _lastSubmittedSkillId = skillId;
    _lastSubmittedSourceText = _normalizeSourceText(sourceText);
    _lastSubmittedHomePromptId = homePromptId;

    _messageSubscription?.cancel();
    _messageController?.close();

    _requestRunner?.cancel();
    final requestRunner = _requestRunner = CancelableLangchainRunner();
    final controller = StreamController<List<ChatMessage>>();
    var requestFailed = false;
    final stream =
        ref.read(aiChatProvider(widget.scope).notifier).sendMessageStream(
              message,
              ref,
              isRegenerate,
              skillId: skillId,
              sourceText: _lastSubmittedSourceText,
              homePromptId: homePromptId,
              requestRunner: requestRunner,
            );

    setState(() {
      _messageController = controller;
      _messageStream = controller.stream;
      _isStreaming = true;
      _replyStartKey = GlobalKey(debugLabel: 'ai-reply-start');
      _showSkillPrompts = false;
    });
    _scrollToBottom();

    _messageSubscription = stream.listen(
      (event) {
        if (controller.isClosed || !identical(_requestRunner, requestRunner)) {
          return;
        }
        controller.add(event);
        _scrollToBottom(force: false);
      },
      onError: (error, stack) {
        if (controller.isClosed || !identical(_requestRunner, requestRunner)) {
          return;
        }
        requestFailed = true;
        controller.addError(error, stack);
        if (!controller.isClosed) {
          controller.close();
        }
        if (mounted) {
          setState(() {
            _isStreaming = false;
            if (inputController.text.isEmpty) inputController.text = message;
          });
        }
      },
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
        if (!identical(_requestRunner, requestRunner)) return;
        if (mounted) {
          setState(() {
            _isStreaming = false;
          });
          if (!requestFailed) {
            _scrollController.returnToReplyStartAfterLayout(_replyStartKey);
          }
        }
      },
      cancelOnError: false,
    );
  }

  void _useQuickPrompt(String prompt) {
    setState(() => _showSkillPrompts = false);
    final subject = inputController.text.trim();
    if (subject.isEmpty) {
      inputController
        ..text = '$prompt '
        ..selection = TextSelection.collapsed(offset: prompt.length + 1);
      _inputFocusNode.requestFocus();
      return;
    }
    inputController.text = '$prompt $subject';
    _sendMessage();
  }

  void _clearMessage() {
    if (_isStreaming) {
      return;
    }
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _messageController?.close();
    _messageController = null;
    setState(() {
      ref.read(aiChatProvider(widget.scope).notifier).clear();
      _showSkillPrompts = false;
      _readerSourceText = null;
      _lastSubmittedSkillId = null;
      _lastSubmittedSourceText = null;
      _lastSubmittedHomePromptId = null;
      _messageStream = null;
    });
  }

  void _regenerateLastMessage() {
    if (_isStreaming) {
      return;
    }
    final messages = ref.read(aiChatProvider(widget.scope)).value;
    if (messages == null || messages.isEmpty) {
      return;
    }

    for (int i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message is HumanChatMessage) {
        setState(() {
          inputController.text = message.contentAsString;
          _sendMessage(
            isRegenerate: true,
            skillId: _lastSubmittedSkillId,
            sourceText: _lastSubmittedSourceText,
            homePromptId: _lastSubmittedHomePromptId,
          );
        });
        break;
      }
    }
  }

  void _copyMessageContent(String content) {
    final parsed = parseReasoningContent(content);
    final clipboardText = _buildCopyableText(parsed, content);
    Clipboard.setData(ClipboardData(text: clipboardText));
    AnxToast.show(L10n.of(context).notesPageCopied);
  }

  void _cancelStreaming() {
    if (!_isStreaming) return;
    _scrollController.stopFollowing();
    _requestRunner?.cancel();
    _requestRunner = null;
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _messageController?.close();
    _messageController = null;
    setState(() {
      _isStreaming = false;
      // Retain the closed stream's last snapshot and its current viewport.
    });
  }

  void _showFontSizeMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = renderBox?.size ?? Size.zero;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy + size.height + 1,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.of(context).aiChatFontSize,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Row(
                    children: [
                      Text(
                        '${_fontSize.round()}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Expanded(
                        child: Slider(
                          value: _fontSize,
                          min: 10.0,
                          max: 24.0,
                          divisions: 14,
                          onChanged: (value) {
                            setMenuState(() {});
                            setState(() {
                              _fontSize = value;
                            });
                            Prefs().aiChatFontSize = value;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  ChatMessage? _getLastAssistantMessage() {
    // The message stream/list already drives rendering. Watching here would
    // also rebuild the entire Scaffold for each partial response.
    final messages = ref.read(aiChatProvider(widget.scope)).asData?.value;
    if (messages == null || messages.isEmpty) {
      return null;
    }

    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i] is AIChatMessage) {
        return messages[i];
      }
    }
    return null;
  }

  Widget _buildSkillPicker(BuildContext context) {
    Widget option({
      required Key key,
      required String label,
      required VoidCallback onPressed,
      IconData icon = Icons.auto_awesome_outlined,
    }) =>
        TextButton.icon(
          key: key,
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          icon: Icon(icon, size: 18),
          label: Text(label),
          onPressed: _isStreaming ? null : onPressed,
        );

    final hasReaderSkills = widget.quickPromptChips.isNotEmpty;
    return Material(
      key: const ValueKey('ai-skill-picker'),
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        key: ValueKey(
            hasReaderSkills ? 'reader-skill-chips' : 'home-quick-prompts'),
        primary: false,
        padding: const EdgeInsets.all(8),
        // Use the conversation viewport, not a growing row above the input.
        // Normal reader skills fit vertically; small windows/large text still
        // allow overflow to scroll without clipping or shrinking tap targets.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasReaderSkills)
              for (final (index, chip) in widget.quickPromptChips.indexed)
                option(
                  key: ValueKey('reader-skill-$index'),
                  label: chip.label,
                  icon: chip.icon,
                  onPressed: () {
                    inputController.text = chip.prompt;
                    _sendMessage(
                        skillId: chip.skillId, sourceText: _readerSourceText);
                  },
                )
            else ...[
              for (final (index, prompt) in _getQuickPrompts(context).indexed)
                option(
                  key: ValueKey('ai-quick-prompt-$index'),
                  label: prompt['label']!,
                  onPressed: () => _useQuickPrompt(prompt['prompt']!),
                ),
              const Divider(),
              for (final prompt in _getStarterPrompts(context))
                option(
                  key: ValueKey('home-prompt-${prompt.id}'),
                  label: prompt.text,
                  onPressed: () {
                    inputController.text = prompt.text;
                    _sendMessage(homePromptId: prompt.id);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allProviders = ref.watch(aiProvidersProvider);
    final enabledProviders = allProviders.where((p) => p.enabled).toList();
    final currentProvider = _currentProvider(enabledProviders);
    final selectedId = Prefs().selectedAiService;

    var aiService = PopupMenuButton<String>(
      enabled: !_isStreaming,
      onSelected: _onProviderSelected,
      itemBuilder: (context) {
        return enabledProviders.map((provider) {
          final isSelected = provider.id == selectedId;
          final label = _modelLabel(provider);
          final logo = _providerLogo(provider);
          return PopupMenuItem<String>(
            value: provider.id,
            child: Row(
              children: [
                if (logo != null) logo else const SizedBox(width: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label.isNotEmpty
                        ? '${provider.title} · $label'
                        : provider.title,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected) const Icon(Icons.check, size: 16),
              ],
            ),
          );
        }).toList(growable: false);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_providerLogo(currentProvider) != null)
            _providerLogo(currentProvider)!,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              currentProvider != null
                  ? () {
                      final label = _modelLabel(currentProvider);
                      return label.isNotEmpty
                          ? '${currentProvider.title} · $label'
                          : currentProvider.title;
                    }()
                  : '',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 16),
        ],
      ),
    );
    Widget inputBox = FilledContainer(
      padding: const EdgeInsets.all(4),
      radius: 15,
      child: SafeArea(
        child: Column(
          children: [
            TextField(
              controller: inputController,
              focusNode: _inputFocusNode,
              decoration: InputDecoration(
                isDense: true,
                hintText: L10n.of(context).aiHintInputPlaceholder,
                border: InputBorder.none,
              ),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: aiService),
                      if (currentProvider != null)
                        IconButton(
                          icon: const Icon(Icons.tune, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          onPressed: () async {
                            final selected = await showModelPickerDialog(
                              context: context,
                              provider: currentProvider,
                              currentModel: currentProvider.model,
                            );
                            if (selected != null &&
                                selected != currentProvider.model) {
                              ref
                                  .read(aiProvidersProvider.notifier)
                                  .updateProvider(
                                    currentProvider.copyWith(model: selected),
                                  );
                            }
                          },
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('ai-skill-prompts-toggle'),
                  tooltip: _showSkillPrompts
                      ? ModuStrings.text(
                          context, '收起技能标签', 'Hide skill shortcuts')
                      : ModuStrings.text(
                          context, '展开技能标签', 'Show skill shortcuts'),
                  isSelected: _showSkillPrompts,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  selectedIcon: const Icon(Icons.auto_awesome, size: 18),
                  onPressed: () {
                    if (!_showSkillPrompts) _inputFocusNode.unfocus();
                    setState(() => _showSkillPrompts = !_showSkillPrompts);
                  },
                ),
                IconButton(
                  icon: Icon(_isStreaming ? Icons.stop : Icons.send, size: 18),
                  onPressed: _isStreaming ? _cancelStreaming : _sendMessage,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(L10n.of(context).aiChat),
        leading: IconButton(
          icon: const Icon(Icons.insert_drive_file),
          tooltip: L10n.of(context).history,
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_document),
            onPressed: _clearMessage,
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showFontSizeMenu(context),
            ),
          ),
          if (widget.trailing != null) ...widget.trailing!,
        ],
      ),
      drawer: Drawer(
        child: _buildHistoryDrawer(context),
      ),
      body: EnvVar.isAppStore &&
              Prefs().shouldShowHint(HintKey.aiDataSharingConsent)
          ? _buildDataSharingConsent(context)
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _messageStream != null
                          ? StreamBuilder<List<ChatMessage>>(
                              stream: _messageStream,
                              builder: (context, snapshot) {
                                if (snapshot.hasError) {
                                  return SingleChildScrollView(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                        snapshot.error
                                            .toString()
                                            .replaceFirst('Bad state: ', ''),
                                        key: const ValueKey('ai-request-error'),
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)),
                                  );
                                }
                                if (!snapshot.hasData) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.done) {
                                    return const SizedBox.expand();
                                  }
                                  return Skeletonizer.zone(
                                      child: Bone.multiText());
                                }

                                final messages = snapshot.data!;
                                if (messages.isEmpty) {
                                  return const SizedBox.expand();
                                }

                                return _buildMessageList(messages);
                              },
                            )
                          : ref.watch(aiChatProvider(widget.scope)).when(
                                data: (messages) {
                                  if (messages.isEmpty) {
                                    return const SizedBox.expand();
                                  }

                                  return _buildMessageList(messages);
                                },
                                loading: () =>
                                    Skeletonizer.zone(child: Bone.multiText()),
                                error: (error, stack) =>
                                    Center(child: Text('error: $error')),
                              ),
                      if (_showSkillPrompts) _buildSkillPicker(context),
                    ],
                  ),
                ),
                inputBox,
              ],
            ),
    );
  }

  Widget _buildDataSharingConsent(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth = MediaQuery.of(context).size.width * 0.9;
    final constrainedWidth = maxWidth > 500 ? 500.0 : maxWidth;

    return Container(
      color: theme.colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constrainedWidth),
            child: FilledContainer(
              padding: const EdgeInsets.all(24),
              radius: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    L10n.of(context).aiDataSharingTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    L10n.of(context).aiDataSharingContent,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  AnxButton(
                    onPressed: () {
                      Prefs().setShowHint(HintKey.aiDataSharingConsent, false);
                      setState(() {});
                    },
                    child: Text(L10n.of(context).aiDataSharingAgree),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages) {
    final latestReplyIndex =
        messages.lastIndexWhere((message) => message is AIChatMessage);
    final sessionId =
        ref.read(aiChatProvider(widget.scope).notifier).currentSessionId;
    final history =
        ref.watch(aiHistoryProvider).value ?? const <AiChatHistoryEntry>[];
    final labels = <int, String>{};
    for (final entry in history) {
      if (entry.id == sessionId) {
        labels.addAll(entry.skillLabels);
        break;
      }
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _scrollController.handleMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: _scrollController.handleNotification,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isStreaming = _isStreaming && index == messages.length - 1;
            return _buildMessageItem(message, index, isStreaming,
                skillLabel: labels[index],
                replyStartKey:
                    index == latestReplyIndex ? _replyStartKey : null);
          },
        ),
      ),
    );
  }

  Widget _buildMessageItem(
    ChatMessage message,
    int index,
    bool isStreaming, {
    String? skillLabel,
    GlobalKey? replyStartKey,
  }) {
    final isUser = message is HumanChatMessage;
    final content = chatMessageDisplayContent(message);
    if (isUser) {
      skillLabel ??= skillMessageLabel(content);
      for (final chip in widget.quickPromptChips) {
        if (skillLabel == null && chip.prompt.trim() == content.trim()) {
          skillLabel = chip.label;
          break;
        }
      }
      if (skillLabel != null) {
        return Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Chip(
              key: ValueKey('ai-message-skill-$index'),
              avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: Text(skillLabel),
            ),
          ),
        );
      }
    }
    final parsed = parseReasoningContent(content);
    final isLongMessage = content.length > 300;
    final lastAssistantMessage = _getLastAssistantMessage();

    return Padding(
      padding: EdgeInsets.only(
        bottom: 8.0,
        left: isUser ? 8.0 : 0,
        right: isUser ? 0 : 8.0,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.surfaceContainer
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: isUser ? const Radius.circular(12) : Radius.zero,
                  topRight: isUser ? Radius.zero : const Radius.circular(12),
                  bottomLeft: isUser ? Radius.zero : const Radius.circular(12),
                  bottomRight: isUser ? const Radius.circular(12) : Radius.zero,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  isUser
                      ? _buildCollapsibleText(content, isLongMessage)
                      : _buildAssistantTimeline(parsed, isStreaming,
                          replyStartKey: replyStartKey),
                  if (!isUser &&
                      identical(message, lastAssistantMessage) &&
                      !_isStreaming &&
                      content.trim().isNotEmpty &&
                      ref
                              .read(aiChatProvider(widget.scope).notifier)
                              .currentDictionarySelection !=
                          null)
                    Padding(
                      key: const ValueKey('dictionary-web-confirmation-hint'),
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(ModuStrings.text(
                          context,
                          '如需联网补查，请在下方输入“确认联网搜索”并发送。',
                          'To check online, type “Confirm online search” below and send.')),
                    ),
                  if (!isUser)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (identical(message, lastAssistantMessage))
                          TextButton(
                            onPressed: _regenerateLastMessage,
                            child: Text(L10n.of(context).aiRegenerate),
                          ),
                        TextButton(
                          onPressed: () => _copyMessageContent(content),
                          child: Text(L10n.of(context).commonCopy),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _buildCopyableText(ParsedReasoning parsed, String fallback) {
    final buffer = StringBuffer();
    var hasWrittenSection = false;

    void startSection() {
      if (hasWrittenSection) {
        buffer.writeln();
      } else {
        hasWrittenSection = true;
      }
    }

    // void appendField(String label, String? value) {
    //   final trimmed = value?.trim();
    //   if (trimmed != null && trimmed.isNotEmpty) {
    //     buffer.writeln('$label: $trimmed');
    //   }
    // }

    for (final entry in parsed.timeline) {
      switch (entry.type) {
        case ParsedReasoningEntryType.reply:
          final text = entry.text?.trim();
          if (text != null && text.isNotEmpty) {
            startSection();
            buffer.writeln(text);
          }
          break;
        case ParsedReasoningEntryType.tool:
          // final step = entry.toolStep;
          // if (step != null) {
          //   startSection();
          //   buffer.writeln('[${step.name} (${step.status})]');
          //   appendField('Input', step.input);
          //   appendField('Output', step.output);
          //   appendField('Error', step.error);
          // }
          break;
      }
    }

    final copyText = buffer.toString().trimRight();
    if (copyText.isEmpty) {
      return fallback;
    }
    return copyText;
  }

  Widget _buildAssistantTimeline(ParsedReasoning parsed, bool isStreaming,
      {GlobalKey? replyStartKey}) {
    if (parsed.timeline.isEmpty) {
      return isStreaming
          ? Skeletonizer.zone(child: Bone.multiText())
          : const SizedBox.shrink();
    }

    final reasoningWidgets = _buildTimelineWidgets(
      parsed.reasoningTimeline,
      fontSize: (_fontSize - 1).clamp(10.0, 24.0).toDouble(),
    );
    final answerWidgets = _buildTimelineWidgets(
      parsed.answerTimeline,
      fontSize: _fontSize,
      replyStartKey: replyStartKey,
    );
    final hasReply = visibleAnswerTimeline(parsed.answerTimeline).any((entry) =>
        entry.type == ParsedReasoningEntryType.reply &&
        (entry.text?.trim().isNotEmpty ?? false));
    final widgets = <Widget>[];

    if (reasoningWidgets.isNotEmpty) {
      widgets.add(_buildThinkingPanel(reasoningWidgets));
    }
    if (answerWidgets.isNotEmpty) {
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 8));
      }
      widgets.addAll(answerWidgets);
    } else if (widgets.isEmpty && isStreaming) {
      widgets.add(Skeletonizer.zone(child: Bone.multiText()));
    }

    return Column(
      // Tool-only replies (such as a generated mind map) use their own start.
      key: hasReply ? null : replyStartKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  List<Widget> _buildTimelineWidgets(
    List<ParsedReasoningEntry> timeline, {
    required double fontSize,
    GlobalKey? replyStartKey,
  }) {
    timeline = visibleAnswerTimeline(timeline);
    final widgets = <Widget>[];
    var firstReply = true;
    for (var i = 0; i < timeline.length; i++) {
      final entry = timeline[i];
      switch (entry.type) {
        case ParsedReasoningEntryType.reply:
          if (entry.text != null && entry.text!.trim().isNotEmpty) {
            widgets.add(
              StyledMarkdown(
                key: firstReply ? replyStartKey : null,
                data: entry.text!,
                selectable: true,
                fontSize: fontSize,
              ),
            );
            firstReply = false;
          }
          break;
        case ParsedReasoningEntryType.tool:
          if (entry.toolStep != null) {
            widgets.add(_buildToolTile(entry.toolStep!));
          }
          break;
      }

      if (i != timeline.length - 1) {
        widgets.add(const SizedBox(height: 8));
      }
    }
    return widgets;
  }

  Widget _buildThinkingPanel(List<Widget> children) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.secondary.withValues(alpha: 0.82);
    final subtleColor = theme.colorScheme.secondary.withValues(alpha: 0.68);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        dense: true,
        visualDensity: VisualDensity.compact,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.fromLTRB(28, 2, 0, 8),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: subtleColor,
        collapsedIconColor: subtleColor,
        leading: Icon(
          Icons.psychology_alt_outlined,
          size: 15,
          color: accentColor,
        ),
        title: Text(
          L10n.of(context).aiThinkingHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: accentColor,
            fontSize: 12,
          ),
        ),
        children: [
          Container(
            margin: const EdgeInsets.only(left: 7),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: subtleColor.withValues(alpha: 0.55),
                  width: 1,
                ),
              ),
            ),
            child: Opacity(
              opacity: 0.9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolTile(ParsedToolStep step) {
    if (step.name == 'bookshelf_organize') {
      return OrganizeBookshelfStepTile(step: step);
    }
    if (step.name == 'mindmap_draw') {
      return MindmapStepTile(step: step);
    }
    if (step.name == 'apply_book_tags') {
      return ApplyBookTagsStepTile(step: step);
    }
    return ToolStepTile(step: step);
  }

  Widget _buildCollapsibleText(String text, bool isLongMessage) {
    if (!isLongMessage) {
      return SelectableText(
        text,
        style: TextStyle(fontSize: _fontSize),
        selectionControls: MaterialTextSelectionControls(),
      );
    }

    return _CollapsibleText(text: text, fontSize: _fontSize);
  }
}

class _CollapsibleText extends StatefulWidget {
  const _CollapsibleText({required this.text, this.fontSize = 14.0});

  final String text;
  final double fontSize;

  @override
  State<_CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<_CollapsibleText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isExpanded)
          SelectableText(
            widget.text,
            style: TextStyle(fontSize: widget.fontSize),
            selectionControls: MaterialTextSelectionControls(),
          )
        else
          Stack(
            children: [
              SelectableText(
                widget.text.substring(0, 300),
                style: TextStyle(fontSize: widget.fontSize),
                selectionControls: MaterialTextSelectionControls(),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainer
                            .withValues(alpha: 0),
                        Theme.of(context).colorScheme.surfaceContainer,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        TextButton(
          onPressed: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: Text(_isExpanded
              ? L10n.of(context).aiHintCollapse
              : L10n.of(context).aiHintExpand),
        ),
      ],
    );
  }
}
