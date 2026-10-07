import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'dart:collection';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/selection_search.dart';
import 'package:anx_reader/page/home_page.dart' show webViewEnvironment;
import 'package:anx_reader/page/settings_page/selection_search.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:anx_reader/widgets/reading_page/selection_search_zoom.dart';
import 'package:anx_reader/widgets/webview/popup_page_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

Future<void> showSelectionSearchBrowser(BuildContext context,
        {required String text}) =>
    showReaderPopup(context,
        // Swiping search results must scroll the page, not dismiss its sheet.
        enableDrag: false,
        builder: (_) => SelectionSearchBrowser(text: text));

/// A separate, unprivileged WebView: no reader scripts or book-data handlers.
class SelectionSearchBrowser extends StatefulWidget {
  const SelectionSearchBrowser(
      {super.key, required this.text, this.pageBuilder});
  final String text;
  @visibleForTesting
  final Widget Function(BuildContext, Uri)? pageBuilder;
  @override
  State<SelectionSearchBrowser> createState() => _SelectionSearchBrowserState();
}

class _SelectionSearchBrowserState extends State<SelectionSearchBrowser> {
  late final _query = TextEditingController(text: widget.text.trim());
  late SelectionSearchConfig _config = Prefs().selectionSearchSettings;
  late Uri _uri = _config.selected.search(widget.text);
  InAppWebViewController? _controller;
  bool _back = false, _forward = false;
  int _progress = 0;
  String? _message;
  late int _zoomPercent = Prefs().selectionSearchZoomPercent;
  Future<void> _zoomQueue = Future<void>.value();
  static const _zoomGroup = 'modu-selection-search-zoom';
  UserScript get _zoomScript => UserScript(
        groupName: _zoomGroup,
        source: selectionSearchZoomScript(_zoomPercent),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        forMainFrameOnly: true,
      );

  // Serialize native script updates so rapid changes cannot restore an older
  // percentage after a newer one. Navigation always reapplies the latest value.
  Future<void> _applyZoom({bool persist = false}) {
    _zoomQueue = _zoomQueue.then((_) async {
      if (!mounted) return;
      try {
        if (persist) {
          await Prefs().saveSelectionSearchZoomPercent(_zoomPercent);
        }
        if (!mounted) return;
        final controller = _controller;
        if (controller == null) return;
        await controller.removeUserScriptsByGroupName(groupName: _zoomGroup);
        if (!mounted || controller != _controller) return;
        await controller.addUserScript(userScript: _zoomScript);
        await controller.evaluateJavascript(
            source: selectionSearchZoomScript(_zoomPercent));
      } catch (_) {
        if (mounted) {
          setState(() => _message = ModuStrings.text(context, '网页缩放失败，请重试。',
              'Could not apply page zoom. Please retry.'));
        }
      }
    });
    return _zoomQueue;
  }

  void _changeZoom(int percent) {
    setState(() {
      _zoomPercent = percent.clamp(50, 200);
      _message = null;
    });
    _applyZoom(persist: true);
  }

  String t(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _action(
      Future<void> Function(InAppWebViewController) action) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await action(controller);
    } catch (_) {
      if (mounted) {
        setState(() => _message = ModuStrings.text(
            context, '网页操作失败，请重试。', 'Page operation failed. Retry.'));
      }
    }
  }

  Future<void> _search() async {
    if (_query.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    final uri = _config.selected.search(_query.text);
    setState(() {
      _uri = uri;
      _message = null;
      _progress = 0;
    });
    await _action(
        (c) => c.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString()))));
  }

  Future<void> _select(String id) async {
    final config =
        SelectionSearchConfig(selectedId: id, custom: _config.custom);
    try {
      await Prefs().saveSelectionSearchSettings(config);
      if (!mounted) return;
      setState(() => _config = config);
      await _search();
    } catch (_) {
      if (mounted) {
        setState(() => _message = ModuStrings.text(
            context, '无法保存搜索引擎，请重试。', 'Could not save the engine. Retry.'));
      }
    }
  }

  Future<void> _settings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
              appBar: AppBar(
                  title: Text(
                      ModuStrings.text(context, '选词搜索', 'Selection search'))),
              body: const SelectionSearchSettings(),
            )));
    if (!mounted) return;
    final old = _config.selected;
    final config = Prefs().selectionSearchSettings;
    setState(() => _config = config);
    if (old.id != config.selected.id ||
        old.template != config.selected.template) {
      await _search();
    }
  }

  Future<void> _history(InAppWebViewController controller, WebUri? url) async {
    try {
      final back = await controller.canGoBack();
      final forward = await controller.canGoForward();
      if (!mounted || controller != _controller) return;
      setState(() {
        _back = back;
        _forward = forward;
        final uri = Uri.tryParse(url?.toString() ?? '');
        if (SelectionSearchEngine.allowsNavigation(uri)) _uri = uri!;
      });
    } catch (_) {/* A closing native view may no longer have history. */}
  }

  bool _allow(WebUri? url) {
    if (SelectionSearchEngine.allowsNavigation(
        Uri.tryParse(url?.toString() ?? ''))) {
      return true;
    }
    if (mounted) {
      setState(() => _message = ModuStrings.text(context, '已阻止打开外部应用或非网页链接。',
          'External apps and non-web links are blocked.'));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_back,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _action((c) => c.goBack());
        },
        child: SafeArea(
            top: false,
            child: LayoutBuilder(
                builder: (context, constraints) => Column(children: [
                      // Keep the native results viewport bounded and usable even with
                      // a landscape keyboard or large accessibility text. Only the
                      // toolbar scrolls; page gestures still belong to the WebView.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight: (constraints.maxHeight - 2)
                                    .clamp(0.0, double.infinity) *
                                0.65),
                        child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(children: [
                                  Expanded(
                                      child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: _config.selectedId,
                                    items: _config.engines
                                        .map((engine) => DropdownMenuItem(
                                            value: engine.id,
                                            child: Text(
                                                engine.label(
                                                    Localizations.localeOf(
                                                                context)
                                                            .languageCode ==
                                                        'zh'),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis)))
                                        .toList(),
                                    onChanged: (id) {
                                      if (id != null) _select(id);
                                    },
                                  )),
                                  IconButton(
                                      tooltip: ModuStrings.text(context,
                                          '搜索引擎设置', 'Search engine settings'),
                                      onPressed: _settings,
                                      icon:
                                          const Icon(Icons.settings_outlined)),
                                  IconButton(
                                      tooltip: ModuStrings.text(
                                          context, '关闭', 'Close'),
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      icon: const Icon(Icons.close)),
                                ])),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: TextField(
                                  controller: _query,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _search(),
                                  decoration: InputDecoration(
                                      isDense: true,
                                      labelText: ModuStrings.text(
                                          context, '搜索内容', 'Search text'),
                                      suffixIcon: IconButton(
                                          tooltip: ModuStrings.text(
                                              context, '搜索', 'Search'),
                                          onPressed: _search,
                                          icon: const Icon(Icons.search))),
                                )),
                            Row(children: [
                              IconButton(
                                  tooltip:
                                      ModuStrings.text(context, '后退', 'Back'),
                                  onPressed: _back
                                      ? () => _action((c) => c.goBack())
                                      : null,
                                  icon: const Icon(Icons.arrow_back)),
                              IconButton(
                                  tooltip: ModuStrings.text(
                                      context, '前进', 'Forward'),
                                  onPressed: _forward
                                      ? () => _action((c) => c.goForward())
                                      : null,
                                  icon: const Icon(Icons.arrow_forward)),
                              IconButton(
                                  tooltip:
                                      ModuStrings.text(context, '刷新', 'Reload'),
                                  onPressed: () {
                                    setState(() => _message = null);
                                    _action((c) => c.reload());
                                  },
                                  icon: const Icon(Icons.refresh)),
                              Expanded(
                                  child: Text(_uri.host,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                              PopupMenuButton<int>(
                                popUpAnimationStyle: AppMotion.style,
                                key: const ValueKey('search-page-zoom'),
                                tooltip: ModuStrings.text(
                                    context, '网页缩放', 'Page zoom'),
                                initialValue: _zoomPercent,
                                onSelected: _changeZoom,
                                itemBuilder: (_) => [
                                  for (final percent in const [
                                    50,
                                    60,
                                    70,
                                    80,
                                    90,
                                    100,
                                    110,
                                    120,
                                    130,
                                    140,
                                    150,
                                    160,
                                    170,
                                    180,
                                    190,
                                    200,
                                  ])
                                    CheckedPopupMenuItem<int>(
                                      value: percent,
                                      checked: percent == _zoomPercent,
                                      child: Text(percent == 100
                                          ? ModuStrings.text(context,
                                              '100%（恢复默认）', '100% (Reset)')
                                          : '$percent%'),
                                    ),
                                ],
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 12),
                                  child: Text('$_zoomPercent%'),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ]),
                            if (_message != null)
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(_message!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                          ]),
                        ),
                      ),
                      SizedBox(
                          height: 2,
                          child: _progress < 100 && widget.pageBuilder == null
                              ? EinkStaticIndicator(
                                  child: LinearProgressIndicator(
                                      value: _progress / 100))
                              : null),
                      Expanded(
                          child: widget.pageBuilder?.call(context, _uri) ??
                              InAppWebView(
                                // Native views otherwise lose vertical drags to ancestor
                                // recognizers. Claim gestures only inside the web page;
                                // the search, engine and close controls stay outside it.
                                gestureRecognizers: {
                                  Factory<OneSequenceGestureRecognizer>(
                                      () => EagerGestureRecognizer()),
                                },
                                webViewEnvironment: webViewEnvironment,
                                initialUrlRequest:
                                    URLRequest(url: WebUri(_uri.toString())),
                                initialUserScripts:
                                    UnmodifiableListView([_zoomScript]),
                                initialSettings: InAppWebViewSettings(
                                  userAgent: popupWebUserAgent,
                                  preferredContentMode:
                                      UserPreferredContentMode.MOBILE,
                                  horizontalScrollBarEnabled: false,
                                  disableHorizontalScroll: true,
                                  disableVerticalScroll: false,
                                  useWideViewPort: false,
                                  loadWithOverviewMode: false,
                                  useShouldOverrideUrlLoading: true,
                                  supportMultipleWindows: true,
                                  javaScriptCanOpenWindowsAutomatically: false,
                                  javaScriptBridgeEnabled: false,
                                  allowFileAccess: false,
                                  allowContentAccess: false,
                                  allowFileAccessFromFileURLs: false,
                                  allowUniversalAccessFromFileURLs: false,
                                  mediaPlaybackRequiresUserGesture: true,
                                  safeBrowsingEnabled: true,
                                ),
                                onWebViewCreated: (controller) =>
                                    _controller = controller,
                                shouldOverrideUrlLoading: (_, action) async =>
                                    _allow(action.request.url)
                                        ? NavigationActionPolicy.ALLOW
                                        : NavigationActionPolicy.CANCEL,
                                onCreateWindow: (controller, action) async {
                                  if (_allow(action.request.url)) {
                                    await _action((c) =>
                                        c.loadUrl(urlRequest: action.request));
                                  }
                                  return false; // Keep all results in this view, never open another app.
                                },
                                onPermissionRequest: (_, request) async =>
                                    PermissionResponse(
                                        resources: request.resources,
                                        action: PermissionResponseAction.DENY),
                                onLoadStart: (_, url) {
                                  if (mounted) {
                                    setState(() {
                                      _progress = 0;
                                      _message = null;
                                    });
                                  }
                                },
                                onProgressChanged: (_, progress) {
                                  if (mounted)
                                    setState(() => _progress = progress);
                                },
                                onLoadStop: (controller, url) async {
                                  if (mounted) setState(() => _progress = 100);
                                  await _applyZoom();
                                  await _history(controller, url);
                                },
                                onUpdateVisitedHistory: (controller, url, _) =>
                                    _history(controller, url),
                                onReceivedError: (_, request, error) {
                                  if (mounted &&
                                      request.isForMainFrame == true) {
                                    setState(() {
                                      _progress = 100;
                                      _message = ModuStrings.text(
                                          context,
                                          '网页加载失败，请刷新或切换搜索引擎。',
                                          'Could not load the page. Reload or switch engines.');
                                    });
                                  }
                                },
                                onReceivedHttpError: (_, request, response) {
                                  if (mounted &&
                                      request.isForMainFrame == true) {
                                    setState(() {
                                      _progress = 100;
                                      _message = ModuStrings.text(
                                          context,
                                          '网站暂时无法访问，请刷新或切换搜索引擎。',
                                          'Website unavailable. Reload or switch engines.');
                                    });
                                  }
                                },
                              )),
                    ]))),
      );
}
