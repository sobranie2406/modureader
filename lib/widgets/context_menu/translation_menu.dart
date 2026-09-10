import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/context_menu/translation_result.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'dart:async';

class TranslationMenu extends StatefulWidget {
  const TranslationMenu({
    super.key,
    required this.content,
    this.contextText,
    this.resultBuilder,
  });
  final String content;
  final String? contextText;
  final Widget Function(String content, String? contextText)? resultBuilder;

  @override
  State<TranslationMenu> createState() => _TranslationMenuState();
}

class _TranslationMenuState extends State<TranslationMenu> {
  Widget? _translationWidget;
  Timer? _debounceTimer;
  bool _translationInitialized = false;
  final ScrollController _scrollController = ScrollController();
  bool _showFullSource = false;

  @override
  void initState() {
    super.initState();
    _initializeTranslation();
  }

  void _initializeTranslation() {
    // Use addPostFrameCallback to ensure the UI is rendered first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _translationInitialized) return;

      // Debounce: Delay the translation call to ensure context has stopped updating
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted || _translationInitialized) return;

        setState(() {
          final effectiveContextText =
              (widget.contextText?.trim().isEmpty ?? true)
                  ? null
                  : widget.contextText;
          _translationWidget = widget.resultBuilder
                  ?.call(widget.content, effectiveContextText) ??
              translateText(
                widget.content,
                contextText: effectiveContextText,
              );
          _translationInitialized = true;
        });
      });
    });
  }

  @override
  void didUpdateWidget(covariant TranslationMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.contextText != widget.contextText) {
      _restartTranslation();
    }
  }

  void _restartTranslation() {
    _debounceTimer?.cancel();
    setState(() {
      _translationInitialized = false;
      _translationWidget = null;
    });
    _initializeTranslation();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _langPicker(bool isFrom) {
    final MenuController menuController = MenuController();

    return PointerInterceptor(
      child: MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.secondaryContainer,
          ),
          maximumSize: WidgetStateProperty.all(const Size(300, 300)),
        ),
        controller: menuController,
        menuChildren: [
          for (var lang in LangListEnum.values)
            PointerInterceptor(
              child: MenuItemButton(
                onPressed: () {
                  if (isFrom) {
                    Prefs().translateFrom = lang;
                  } else {
                    Prefs().translateTo = lang;
                  }
                  _restartTranslation();
                },
                child: Text(lang.getNative(context)),
              ),
            ),
        ],
        builder: (context, controller, child) {
          return TextButton(
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Text(
              isFrom
                  ? Prefs().translateFrom.getNative(context)
                  : Prefs().translateTo.getNative(context),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Icon(Icons.translate_outlined),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(l10n.contextMenuTranslate,
                      style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child:
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              _langPicker(true),
              const Icon(Icons.arrow_forward, size: 16),
              _langPicker(false),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const ValueKey('selection-translation-scroll'),
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                child: TranslationResult(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.content,
                            key: const ValueKey('selection-translation-source'),
                            maxLines: _showFullSource ? null : 3,
                            overflow: _showFullSource
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, height: 1.5)),
                        TextButton(
                          onPressed: () => setState(
                              () => _showFullSource = !_showFullSource),
                          child: Text(_showFullSource
                              ? (zh ? '收起原文' : 'Collapse original')
                              : (zh ? '展开原文' : 'Expand original')),
                        ),
                        const Divider(),
                        _translationWidget ?? const Text('...'),
                      ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
