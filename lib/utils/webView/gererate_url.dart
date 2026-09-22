import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/book_player/reading_appearance.dart';
import 'package:anx_reader/utils/js/convert_dart_color_to_js.dart';
import 'package:anx_reader/utils/platform_utils.dart';

String generateUrl(
  String url,
  String cfi, {
  BookStyle? bookStyle,
  int? textIndent,
  String? textColor,
  String? fontName,
  String? fontPath,
  String? backgroundColor,
  bool? importing,
  bool isDarkMode = false,
  Map<String, double>? verticalPageInsets,
  Map<String, dynamic>? verticalPageChrome,
  String? cssBookKey,
}) {
  String indexHtmlPath =
      "http://127.0.0.1:${Server().port}/foliate-js/index.html";

  ReadTheme readTheme = readingThemeForDisplay(Prefs());
  bookStyle ??= Prefs().bookStyle;
  textColor ??= readTheme.textColor;
  fontName ??= Prefs().font.name;
  fontPath ??= Prefs().font.path;
  backgroundColor ??= readTheme.backgroundColor;
  importing ??= false;

  textColor = convertDartColorToJs(textColor);
  backgroundColor = convertDartColorToJs(backgroundColor);

  // Get effective background image URL using the new method
  String bgimgUrl = readingBackgroundForDisplay(Prefs(), isDarkMode: isDarkMode);
  // const importing = $importing
  // const url = '${replaceSingleQuote(url)}'
  // let initialCfi = '${replaceSingleQuote(cfi)}'
  // let style = {
  //     fontSize: ${bookStyle.fontSize},
  //     fontName: '${replaceSingleQuote(fontName)}',
  //     fontPath: '${replaceSingleQuote(fontPath)}',
  //     fontWeight: ${bookStyle.fontWeight},
  //     letterSpacing: ${bookStyle.letterSpacing},
  //     spacing: ${bookStyle.lineHeight},
  //     paragraphSpacing: ${bookStyle.paragraphSpacing},
  //     textIndent: ${bookStyle.indent},
  //     fontColor: '#$textColor',
  //     backgroundColor: '#$backgroundColor',
  //     topMargin: ${bookStyle.topMargin},
  //     bottomMargin: ${bookStyle.bottomMargin},
  //     sideMargin: ${bookStyle.sideMargin},
  //     justify: true,
  //     hyphenate: true,
  //     pageTurnStyle: '${Prefs().pageTurnStyle.name}',
  //     maxColumnCount: ${bookStyle.maxColumnCount},
  // }

  // let readingRules = {
  //   convertChineseMode: '${Prefs().readingRules.convertChineseMode.name}',
  //   bionicReadingMode: ${Prefs().readingRules.bionicReading},
  // }

  Map<String, dynamic> style = {
    // These are needed on first open, not only after changing reader settings.
    // In particular, native WebView focus bypasses Flutter's page shortcuts.
    'desktopPageInput': AnxPlatform.isDesktop,
    'keyboardShortcutTurnPage': Prefs().keyboardShortcutTurnPage,
    'mobileTouchPaging': AnxPlatform.isMobile,
    'mobileImageFit': AnxPlatform.isMobile,
    'tapOnlyPageTurn': Prefs().tapOnlyPageTurn,
    'eInkMode': Prefs().eInkMode,
    'fontSize': bookStyle.fontSize,
    'fontName': fontName,
    'fontPath': fontPath,
    'englishFontName': Prefs().englishFont?.name,
    'englishFontPath': Prefs().englishFont?.path,
    'fontWeight': bookStyle.fontWeight,
    'letterSpacing': bookStyle.letterSpacing,
    'spacing': bookStyle.lineHeight,
    'paragraphSpacing': bookStyle.paragraphSpacing,
    'textIndent': bookStyle.indent,
    'fontColor': '#$textColor',
    'backgroundColor': '#$backgroundColor',
    'topMargin': bookStyle.topMargin,
    'bottomMargin': bookStyle.bottomMargin,
    'sideMargin': bookStyle.sideMargin,
    'justify': true,
    'hyphenate': false,
    'pageTurnStyle': Prefs().pageTurnStyle.name,
    'maxColumnCount': bookStyle.maxColumnCount,
    'columnThreshold': bookStyle.columnThreshold,
    'writingMode': Prefs().writingMode.code,
    // Only the visible reader supplies chrome; headless import/search does not.
    'verticalPageInsets': verticalPageInsets,
    'verticalPageChrome': verticalPageChrome,
    'verticalRedFrame': Prefs().verticalRedFrame,
    'textAlign': Prefs().textAlignment.code,
    'backgroundImage': bgimgUrl,
    'bgimgBlur': Prefs().bgimg.blur,
    'bgimgOpacity': Prefs().bgimg.opacity,
    'bgimgFit': Prefs().bgimgFit.code,
    'allowScript': Prefs().enableJsForEpub,
    // WKWebView and WPE WebKit need iframe script permission for reader-owned
    // DOM events. EPUB sanitization/CSP remains controlled solely by allowScript.
    'readerScriptEvents':
        AnxPlatform.isMacOS || AnxPlatform.isIOS || AnxPlatform.isLinux,
    'customCSS': Prefs().customCssForBook(cssBookKey),
    'customCSSEnabled': Prefs().customCssSelection(cssBookKey).enabled,
    'useBookStyles': Prefs().useBookStyles,
    'headingFontSize': bookStyle.headingFontSize,
    'codeHighlightTheme': Prefs().codeHighlightTheme.code,
  };

  Map<String, dynamic> readingRules = {
    'convertChineseMode': Prefs().readingRules.convertChineseMode.name,
    'bionicReadingMode': Prefs().readingRules.bionicReading,
  };

  Map<String, dynamic> params = {
    'importing': importing,
    'url': url,
    'initialCfi': cfi,
    'style': style,
    'readingRules': readingRules,
  };

  String query = '';

  for (var key in params.keys) {
    query += '$key=${Uri.encodeComponent(jsonEncode(params[key]))}&';
  }
  //remove last &
  query = query.substring(0, query.length - 1);

  // query += 'importing=$importing';
  // query += '&url=$url';
  // query += '&initialCfi=$cfi';
  // query += '&style=$style';
  // query += '&readingRules=$readingRules';
  // query += '&style=$style';
  // query += '&readingRules=$readingRules';

  final uri = '$indexHtmlPath?$query';

  return uri;
}
