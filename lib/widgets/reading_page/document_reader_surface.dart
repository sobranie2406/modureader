import 'brightness_widget.dart';
import 'package:anx_reader/service/app_brightness.dart';
import 'reader_menu_appearance.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:anx_reader/enums/bgimg_fit.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/book_player/reading_appearance.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'reader_popup.dart';
import 'reader_settings_scroll_view.dart';

/// Ebook chrome over the existing document reader. Menus must not resize the
/// text viewport, invalidate its selection, or restart page recognition.
class DocumentReaderSurface extends StatefulWidget {
  const DocumentReaderSurface(
      {super.key,
      required this.header,
      required this.body,
      required this.navigation,
      required this.tools,
      required this.style,
      this.actions = const [],
      this.extraMenus = const {},
      this.brightness,
      this.narration,
      this.readerContentOnly = false,
      this.inlineTools = false,
      this.hideHeader = false,
      this.onMenuOpened,
      this.onBack});
  final Widget header, body, navigation, tools, style;
  final List<Widget> actions;
  final Map<String, Widget> extraMenus;
  final Widget? brightness, narration;
  final bool readerContentOnly, inlineTools;
  final bool hideHeader;
  final VoidCallback? onMenuOpened, onBack;

  @override
  State<DocumentReaderSurface> createState() => DocumentReaderSurfaceState();
}

class DocumentReaderSurfaceState extends State<DocumentReaderSurface> {
  String? _menu;
  bool get menuIsOpen => _menu != null;
  void closeMenu() {
    if (mounted) setState(() => _menu = null);
  }

  void openMenu(String menu, {bool toggle = true}) {
    if (widget.inlineTools && menu != 'narration') return;
    widget.onMenuOpened?.call();
    setState(() => _menu = toggle && _menu == menu ? null : menu);
  }

  @override
  void didUpdateWidget(covariant DocumentReaderSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((_menu == 'narration' && widget.narration == null) ||
        (_menu == 'brightness' && widget.brightness == null)) {
      _menu = null;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Prefs(),
      builder: (context, _) {
        final theme = readingThemeForDisplay(Prefs(),
            isDarkMode: Theme.of(context).brightness == Brightness.dark);
        Color color(String value, Color fallback) =>
            Color(int.tryParse(value.replaceFirst('#', ''), radix: 16) ??
                    fallback.toARGB32())
                .withAlpha(255);
        final background =
            color(theme.backgroundColor, Theme.of(context).colorScheme.surface);
        final foreground =
            color(theme.textColor, Theme.of(context).colorScheme.onSurface);
        final backgroundUrl = readingBackgroundForDisplay(Prefs(),
            isDarkMode: Theme.of(context).brightness == Brightness.dark);
        Widget readingColors(Widget child) => Theme(
            data: Theme.of(context).copyWith(
                textTheme: Theme.of(context)
                    .textTheme
                    .apply(bodyColor: foreground, displayColor: foreground),
                iconTheme: IconThemeData(color: foreground),
                colorScheme: Theme.of(context)
                    .colorScheme
                    .copyWith(surface: background, onSurface: foreground)),
            child: DefaultTextStyle.merge(
                style: TextStyle(color: foreground), child: child));
        String label(String menu, String zh, String en) => _menu == menu
            ? ModuStrings.text(context, '收起菜单', 'Hide menu')
            : ModuStrings.text(context, zh, en);
        if (widget.inlineTools) {
          return Material(
              color: background,
              child: SafeArea(
                  child: Column(children: [
                ReaderMenuAppearance.wrap(
                    context, readingColors(widget.header)),
                Expanded(
                    flex: 5,
                    child: AppBrightnessLayer(
                        controller: AppBrightness.instance,
                        child: readingColors(widget.body))),
                widget.navigation,
                Expanded(
                    flex: 4,
                    child: ScrollConfiguration(
                        behavior: const MaterialScrollBehavior()
                            .copyWith(scrollbars: false),
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(children: [
                              if (widget.narration != null) ...[
                                IconButton(
                                    tooltip:
                                        label('narration', '朗读', 'Read aloud'),
                                    icon: const Icon(EvaIcons.headphones),
                                    onPressed: () => openMenu('narration')),
                                if (_menu == 'narration') widget.narration!,
                              ],
                              widget.tools,
                            ])))),
              ])));
        }
        final toolbar = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Row(
                key: const ValueKey('document-reader-toolbar'),
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  ...widget.actions,
                  IconButton(
                      key: const ValueKey('document-style-menu'),
                      tooltip: label('style', '样式', 'Style'),
                      isSelected: _menu == 'style',
                      icon: const Icon(Icons.color_lens),
                      onPressed: () => openMenu('style')),
                  if (widget.brightness != null)
                    IconButton(
                        tooltip: label(
                            'brightness', '亮度 / 配色', 'Brightness / colors'),
                        icon: const Icon(Icons.brightness_6_outlined),
                        onPressed: () => openMenu('brightness')),
                  if (widget.narration != null)
                    IconButton(
                        tooltip: label('narration', '朗读', 'Read aloud'),
                        icon: const Icon(EvaIcons.headphones),
                        onPressed: () => openMenu('narration')),
                  IconButton(
                      key: const ValueKey('document-tools-menu'),
                      tooltip: label(
                          'tools', '识别 / 原页', 'Recognition / original page'),
                      isSelected: _menu == 'tools',
                      icon: const Icon(Icons.document_scanner_outlined),
                      onPressed: () => openMenu('tools')),
                ]));
        return PopScope(
            canPop: _menu == null && widget.onBack == null,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_menu != null) {
                closeMenu();
              } else {
                widget.onBack?.call();
              }
            },
            child: Material(
                key: const ValueKey('document-reader-background'),
                animationDuration: Duration.zero,
                color: background,
                child: SafeArea(
                    child: LayoutBuilder(
                        builder: (context, viewport) => Column(children: [
                              Expanded(
                                  child: LayoutBuilder(
                                      builder: (context, bodySpace) =>
                                          Stack(children: [
                                            if (backgroundUrl != 'none')
                                              Positioned.fill(
                                                  child: IgnorePointer(
                                                      child: ClipRect(
                                                          child: ImageFiltered(
                                                              imageFilter: ui.ImageFilter.blur(
                                                                  sigmaX: Prefs()
                                                                      .bgimg
                                                                      .blur,
                                                                  sigmaY: Prefs()
                                                                      .bgimg
                                                                      .blur),
                                                              child: Opacity(
                                                                  opacity: Prefs()
                                                                      .bgimg
                                                                      .opacity
                                                                      .clamp(
                                                                          0, 1),
                                                                  child: Image.network(backgroundUrl,
                                                                      alignment: Prefs()
                                                                          .bgimg
                                                                          .alignment
                                                                          .alignment,
                                                                      fit: Prefs().bgimgFit == BgimgFitEnum.stretch ? BoxFit.fill : BoxFit.cover,
                                                                      errorBuilder: (context, error, stack) => const SizedBox.shrink())))))),
                                            Column(children: [
                                              Visibility(
                                                  visible: _menu == null &&
                                                      !widget.hideHeader,
                                                  maintainState: true,
                                                  maintainAnimation: true,
                                                  maintainSize: true,
                                                  child:
                                                      ReaderMenuAppearance.wrap(
                                                          context,
                                                          readingColors(
                                                              widget.header))),
                                              Expanded(
                                                  child: AppBrightnessLayer(
                                                      controller: AppBrightness
                                                          .instance,
                                                      child: readingColors(
                                                          widget.body))),
                                            ]),
                                            if (_menu != null) ...[
                                              Positioned.fill(
                                                  child: GestureDetector(
                                                      onTap: closeMenu,
                                                      behavior: HitTestBehavior
                                                          .opaque,
                                                      child: ColoredBox(
                                                          color: Colors
                                                              .transparent))),
                                              Align(
                                                  alignment:
                                                      Alignment.bottomCenter,
                                                  child: ReaderMenuAppearance.wrap(
                                                      context,
                                                      BottomSheet(
                                                          enableDrag: false,
                                                          onClosing: closeMenu,
                                                          constraints: ReaderPopup.constraints(context),
                                                          builder: (context) => ConstrainedBox(
                                                              constraints: BoxConstraints(maxHeight: math.max(0, ReaderPopup.height(context) - (viewport.maxHeight - bodySpace.maxHeight))),
                                                              child: ReaderQuickStylePanel(
                                                                  content: Padding(
                                                                      padding: _menu == 'style' ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                                                      child: _menu == 'style'
                                                                          ? widget.style
                                                                          : ReaderSettingsScrollView(
                                                                              child: _menu == 'brightness'
                                                                                  ? widget.brightness!
                                                                                  : _menu == 'narration'
                                                                                      ? widget.narration!
                                                                                      : widget.extraMenus[_menu] ?? widget.tools)),
                                                                  toolbar: const SizedBox.shrink()))))),
                                            ],
                                          ]))),
                              Material(
                                  animationDuration: Duration.zero,
                                  color: ReaderMenuAppearance.background(
                                      context,
                                      _menu == null
                                          ? background
                                          : Theme.of(context)
                                              .colorScheme
                                              .surface),
                                  child: ReaderMenuAppearance.wrap(
                                      context,
                                      ConstrainedBox(
                                          constraints:
                                              ReaderPopup.constraints(context),
                                          child: _menu == null
                                              ? readingColors(Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                      widget.navigation,
                                                      if (!widget
                                                          .readerContentOnly)
                                                        toolbar
                                                    ]))
                                              : Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                      widget.navigation,
                                                      if (!widget
                                                          .readerContentOnly)
                                                        toolbar
                                                    ])))),
                            ])))));
      });
}
