import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/service/translate/web_prefill.dart';
import 'package:anx_reader/page/home_page.dart' show webViewEnvironment;
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
    final url = getUrl(text, from, to);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (prefillScript(text) != null) ...[
        Builder(
            builder: (context) => Text(ModuStrings.text(
                context,
                '若网页未自动填入，请复制原文后粘贴；目标语言在网页内选择。',
                'If the text is not filled in automatically, copy and paste it. Choose the target language on the page.'))),
        Builder(
            builder: (context) => TextButton.icon(
                key: const ValueKey('web-translation-copy-source'),
                icon: const Icon(Icons.copy),
                label: Text(L10n.of(context).commonCopy),
                onPressed: () => Clipboard.setData(ClipboardData(text: text)))),
      ],
      SizedBox(
        height: 400,
        child: Stack(
          children: [
            InAppWebView(
              webViewEnvironment: webViewEnvironment,
              initialUrlRequest: URLRequest(url: WebUri(url)),
              initialSettings: InAppWebViewSettings(
                isInspectable: kDebugMode,
                javaScriptBridgeEnabled: false,
                useShouldOverrideUrlLoading: true,
                allowFileAccess: false,
                allowContentAccess: false,
                allowFileAccessFromFileURLs: false,
                allowUniversalAccessFromFileURLs: false,
                mediaPlaybackRequiresUserGesture: true,
                allowsInlineMediaPlayback: true,
              ),
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
                final script = prefillScript(text);
                if (script != null) {
                  try {
                    await controller.evaluateJavascript(source: script);
                  } catch (_) {/* The visible copy button remains usable. */}
                }
              },
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Builder(
                builder: (context) {
                  return Material(
                    color: Theme.of(context).cardColor.withAlpha(200),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.open_in_new, size: 20),
                      onPressed: () {
                        launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      )
    ]);
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
      _useMobileTranslationPage
          ? 'https://fanyi.baidu.com/m/trans'
          : 'https://fanyi.baidu.com/mtpe-individual/transText';
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
      _useMobileTranslationPage
          ? 'https://m.youdao.com/translate'
          : 'https://fanyi.youdao.com/index.html';
  @override
  String prefillScript(String text) => webTranslationPrefillScript(
      host: 'fanyi.youdao.com',
      selector: '.prompt-question-normal[contenteditable="true"]',
      additionalEditors: const {'m.youdao.com': 'textarea#inputText'},
      text: text);
}

bool get _useMobileTranslationPage =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
