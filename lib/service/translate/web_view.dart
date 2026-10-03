import 'dart:collection';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/service/translate/web_prefill.dart';
import 'package:anx_reader/page/home_page.dart' show webViewEnvironment;
import 'package:anx_reader/widgets/webview/page_zoom_button.dart';
import 'package:anx_reader/widgets/webview/popup_page_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:url_launcher/url_launcher.dart';

/// Base class for WebView-based translation providers.
abstract class WebViewTranslateProvider extends TranslateServiceProvider {
  /// Constructs the URL for the translation service.
  String getUrl(String text, LangListEnum from, LangListEnum to);

  String? prefillScript(String text) => null;

  @override
  Widget translate(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
  }) {
    return WebTranslationView(
      key: ValueKey((service, text, from, to)),
      url: getUrl(text, from, to),
      text: text,
      prefill: prefillScript(text),
    );
  }

  @override
  Stream<String> translateStream(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
  }) async* {
    // WebView providers do not support stream translation
    yield "...";
  }

  @override
  Future<String> translateTextOnly(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
  }) async {
    // WebView providers do not support text-only translation
    return "";
  }
}

/// Page controls stay outside the native view so they cannot cover a result.
class WebTranslationView extends StatefulWidget {
  const WebTranslationView(
      {super.key, required this.url, required this.text, this.prefill});
  final String url;
  final String text;
  final String? prefill;

  @override
  State<WebTranslationView> createState() => _WebTranslationViewState();
}

class _WebTranslationViewState extends State<WebTranslationView> {
  InAppWebViewController? _controller;
  late int _zoomPercent = Prefs().webTranslationZoomPercent;
  Future<void> _zoomQueue = Future<void>.value();
  String? _error;
  static const _layoutGroup = 'modu-web-translation-layout';
  UserScript get _layoutScript => UserScript(
        groupName: _layoutGroup,
        source: popupPageLayoutScript(_zoomPercent),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        forMainFrameOnly: true,
      );

  Future<void> _applyZoom({bool persist = false}) {
    _zoomQueue = _zoomQueue.then((_) async {
      if (!mounted) return;
      try {
        if (persist) await Prefs().saveWebTranslationZoomPercent(_zoomPercent);
        if (!mounted) return;
        final controller = _controller;
        if (controller == null) return;
        await controller.removeUserScriptsByGroupName(groupName: _layoutGroup);
        if (!mounted || controller != _controller) return;
        await controller.addUserScript(userScript: _layoutScript);
        await controller.evaluateJavascript(
            source: popupPageLayoutScript(_zoomPercent));
      } catch (_) {
        if (mounted)
          setState(() => _error = ModuStrings.text(context, '网页缩放失败，请重试。',
              'Could not apply page zoom. Please retry.'));
      }
    });
    return _zoomQueue;
  }

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        if (widget.prefill != null)
          Text(ModuStrings.text(context, '若网页未自动填入，请复制原文后粘贴；目标语言在网页内选择。',
              'If the text is not filled in automatically, copy and paste it. Choose the target language on the page.')),
        // Wrap on narrow popups/large accessibility text instead of overflowing.
        Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.prefill != null)
                  TextButton.icon(
                    key: const ValueKey('web-translation-copy-source'),
                    icon: const Icon(Icons.copy),
                    label: Text(L10n.of(context).commonCopy),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: widget.text)),
                  ),
                PageZoomButton(
                  key: const ValueKey('translation-page-zoom'),
                  percent: _zoomPercent,
                  onChanged: (value) {
                    setState(() {
                      _zoomPercent = value.clamp(50, 200);
                      _error = null;
                    });
                    _applyZoom(persist: true);
                  },
                ),
                IconButton(
                  tooltip:
                      ModuStrings.text(context, '在浏览器中打开', 'Open in browser'),
                  icon: const Icon(Icons.open_in_new, size: 20),
                  onPressed: () => launchUrl(Uri.parse(widget.url),
                      mode: LaunchMode.externalApplication),
                ),
              ],
            )),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        SizedBox(
          height: 400,
          child: InAppWebView(
            webViewEnvironment: webViewEnvironment,
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialUserScripts: UnmodifiableListView([_layoutScript]),
            initialSettings: InAppWebViewSettings(
              userAgent: popupWebUserAgent,
              preferredContentMode: UserPreferredContentMode.MOBILE,
              isInspectable: kDebugMode,
              horizontalScrollBarEnabled: false,
              disableHorizontalScroll: true,
              disableVerticalScroll: false,
              useWideViewPort: false,
              loadWithOverviewMode: false,
              javaScriptBridgeEnabled: false,
              useShouldOverrideUrlLoading: true,
              allowFileAccess: false,
              allowContentAccess: false,
              allowFileAccessFromFileURLs: false,
              allowUniversalAccessFromFileURLs: false,
              mediaPlaybackRequiresUserGesture: true,
              allowsInlineMediaPlayback: true,
            ),
            onWebViewCreated: (controller) => _controller = controller,
            shouldOverrideUrlLoading: (_, action) async {
              final uri = Uri.tryParse(action.request.url?.toString() ?? '');
              return uri != null &&
                      (uri.scheme == 'https' || uri.scheme == 'http')
                  ? NavigationActionPolicy.ALLOW
                  : NavigationActionPolicy.CANCEL;
            },
            onPermissionRequest: (_, request) async => PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.DENY),
            onLoadStop: (controller, _) async {
              await _applyZoom();
              if (!mounted || controller != _controller) return;
              final script = widget.prefill;
              if (script != null) {
                try {
                  await controller.evaluateJavascript(source: script);
                } catch (_) {/* The visible copy button remains usable. */}
              }
            },
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer()),
            },
          ),
        ),
      ]);
}

class BingWebTranslateProvider extends WebViewTranslateProvider {
  @override
  TranslateService get service => TranslateService.bingWeb;

  @override
  String getLabel(BuildContext context) => L10n.of(context).translateBingWeb;

  /// Bing uses 'auto-detect' for auto language detection.
  @override
  String mapLanguageCode(LangListEnum lang) {
    if (lang == LangListEnum.auto) return 'auto-detect';
    return lang.code;
  }

  @override
  String getUrl(String text, LangListEnum from, LangListEnum to) {
    return 'https://www.bing.com/translator?from=${mapLanguageCode(from)}&to=${mapLanguageCode(to)}&text=${Uri.encodeComponent(text)}';
  }
}

class GoogleWebTranslateProvider extends WebViewTranslateProvider {
  @override
  TranslateService get service => TranslateService.googleWeb;

  @override
  String getLabel(BuildContext context) => L10n.of(context).translateGoogleWeb;

  /// Google uses 'auto' for auto language detection.
  @override
  String mapLanguageCode(LangListEnum lang) {
    if (lang == LangListEnum.auto) return 'auto';
    return lang.code;
  }

  @override
  String getUrl(String text, LangListEnum from, LangListEnum to) {
    return 'https://translate.google.com/?sl=${mapLanguageCode(from)}&tl=${mapLanguageCode(to)}&text=${Uri.encodeComponent(text)}&op=translate';
  }
}

class BaiduWebTranslateProvider extends WebViewTranslateProvider {
  @override
  TranslateService get service => TranslateService.baiduWeb;
  @override
  String getLabel(BuildContext context) =>
      ModuStrings.text(context, '百度网页翻译', 'Baidu Web Translate');
  @override
  String getUrl(String text, LangListEnum from, LangListEnum to) =>
      'https://fanyi.baidu.com/m/trans';
  @override
  String prefillScript(String text) => webTranslationPrefillScript(
      host: 'fanyi.baidu.com',
      selector: '[role="textbox"][contenteditable="true"], '
          'textarea.taro-textarea[placeholder="输入要翻译的单词或句子..."]',
      text: text);
}

class YoudaoWebTranslateProvider extends WebViewTranslateProvider {
  @override
  TranslateService get service => TranslateService.youdaoWeb;
  @override
  String getLabel(BuildContext context) =>
      ModuStrings.text(context, '有道网页翻译', 'Youdao Web Translate');
  @override
  String getUrl(String text, LangListEnum from, LangListEnum to) =>
      'https://m.youdao.com/translate';
  @override
  String prefillScript(String text) => webTranslationPrefillScript(
      host: 'fanyi.youdao.com',
      selector: '.prompt-question-normal[contenteditable="true"]',
      additionalEditors: const {'m.youdao.com': 'textarea#inputText'},
      text: text);
}
