import 'dart:core';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/config/config_item.dart';
import 'package:anx_reader/service/translate/translate_registry.dart';
import 'package:anx_reader/service/translate/web_view.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TranslateService {
  microsoftFree,
  bingWeb,
  googleWeb,
  microsoftApi,
  googleApi,
  deepl,
  ai,
  baiduApi,
  baiduWeb,
  youdaoWeb;

  /// Built-in providers, resolved through [TranslateRegistry].
  ///
  /// The enum stays because its `name` is the persisted token in
  /// 'translateService' and 'fullTextTranslateService', and the suffix of
  /// 'translateServiceConfig_...'. P2 moved the table to a registry without
  /// renaming a single id.
  TranslateServiceProvider get provider =>
      TranslateRegistry.current.providerFor(name);


  /// Get the display label from the provider.
  String getLabel(BuildContext context) => provider.getLabel(context);

  /// Check if the service is a WebView provider.
  bool get isWebView => provider is WebViewTranslateProvider;

  /// These sites choose language inside their own page, not via URL parameters.
  bool get usesPageLanguagePicker =>
      this == TranslateService.baiduWeb || this == TranslateService.youdaoWeb;

  static List<TranslateService> get activeValues =>
      TranslateRegistry.current.activeValues;

  /// Providers displayed by ReadAny's translation settings.
  static List<TranslateService> get readAnyValues =>
      TranslateRegistry.current.readAnyValues;

  static List<TranslateService> get webValues =>
      TranslateRegistry.current.webValues;

  static List<TranslateService> get selectionValues =>
      TranslateRegistry.current.selectionValues;
}

TranslateService getTranslateService(String name) =>
    TranslateRegistry.current.resolveService(name) ??
    TranslateService.microsoftFree;

/// Base class for all translation service providers.
/// Subclasses must implement [service], [label], [translate], and [translateStream].
abstract class TranslateServiceProvider {
  /// The service enum value this provider corresponds to.
  TranslateService get service;

  /// The display label for this service.
  String getLabel(BuildContext context);

  /// Override this method if the service uses a different code format.
  /// Default implementation returns [lang.code].
  String mapLanguageCode(LangListEnum lang) => lang.code;

  /// Get the configuration items for this service.
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [];
  }

  /// Returns the widget for displaying the translation result.
  Widget translate(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
  });

  /// Returns a stream of translation results.
  Stream<String> translateStream(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
  });

  /// Translate text only (no widget), with retry logic.
  Future<String> translateTextOnly(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
  }) async {
    const int maxRetries = 2;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        String? lastResult;
        await for (String result in translateStream(
          text,
          from,
          to,
          contextText: contextText,
          isFullText: isFullText,
        )) {
          lastResult = result;
        }

        if (lastResult != null &&
            lastResult.trim().isNotEmpty &&
            lastResult != '...') {
          return lastResult;
        }

        throw Exception(
            'Translation returned no valid result: ${lastResult ?? 'No result'}');
      } catch (e) {
        if (attempt < maxRetries) {
          AnxLog.warning(
              'Translation attempt ${attempt + 1} failed with exception: $e. Retrying...');
          await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
          continue;
        } else {
          throw Exception(
              'Translation failed after ${maxRetries + 1} attempts: $e');
        }
      }
    }

    throw Exception('Translation failed after all retry attempts');
  }

  /// Returns the current configuration.
  Map<String, dynamic> getConfig() => {};

  /// Saves the configuration.
  void saveConfig(Map<String, dynamic> config) {}

  /// Helper to convert a stream to a widget with copy button.
  Widget convertStreamToWidget(Stream<String> stream) {
    return StreamBuilder<String>(
      stream: stream,
      builder: (context, snapshot) {
        Widget content() {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Text('...');
          } else if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else if (snapshot.hasData) {
            return Text(snapshot.data!);
          } else {
            return const Text('');
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            content(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: snapshot.data!)),
                    child: Text(L10n.of(context).commonCopy))
              ],
            )
          ],
        );
      },
    );
  }
}

// ============================================================================
// Helper functions (use service.provider instead of TranslateFactory)
// ============================================================================

Widget translateText(String text,
    {TranslateService? service, String? contextText}) {
  service ??= Prefs().translateService;
  final from = Prefs().translateFrom;
  final to = Prefs().translateTo;

  return service.provider.translate(
    text,
    from,
    to,
    contextText: contextText,
  );
}

List<ConfigItem> getTranslateServiceConfigItems(
    BuildContext context, TranslateService service) {
  return service.provider.getConfigItems(context);
}

Map<String, dynamic> getTranslateServiceConfig(TranslateService service) {
  return service.provider.getConfig();
}

void saveTranslateServiceConfig(
    TranslateService service, Map<String, dynamic> config) {
  return service.provider.saveConfig(config);
}

Future<String> translateTextOnly(String text,
    {TranslateService? service, String? contextText}) async {
  service ??= Prefs().translateService;
  final from = Prefs().translateFrom;
  final to = Prefs().translateTo;

  return await service.provider.translateTextOnly(
    text,
    from,
    to,
    contextText: contextText,
  );
}