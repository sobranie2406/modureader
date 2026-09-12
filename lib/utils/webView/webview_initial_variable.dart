import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/utils/js/convert_dart_color_to_js.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

Future<void> webviewInitialVariable(
  InAppWebViewController controller,
  String url,
  String cfi, {
  BookStyle? bookStyle,
  int? textIndent,
  String? textColor,
  String? fontName,
  String? fontPath,
  String? backgroundColor,
  bool? importing,
}) async {
  ReadTheme readTheme = Prefs().readTheme;
  bookStyle ??= Prefs().bookStyle;
  textColor ??= readTheme.textColor;
  fontName ??= Prefs().font.name;
  fontPath ??= Prefs().font.path;
  backgroundColor ??= readTheme.backgroundColor;
  importing ??= false;

  textColor = convertDartColorToJs(textColor);
  backgroundColor = convertDartColorToJs(backgroundColor);

  String replaceSingleQuote(String value) {
    return value.replaceAll("'", "\\'");
  }

  final script = '''
      const importing = $importing
      const url = '${replaceSingleQuote(url)}'
      let initialCfi = '${replaceSingleQuote(cfi)}'
      let style = {
          desktopPageInput: ${AnxPlatform.isDesktop},
          mobileTouchPaging: ${AnxPlatform.isMobile},
          mobileImageFit: ${AnxPlatform.isMobile},
          tapOnlyPageTurn: ${Prefs().tapOnlyPageTurn},
          eInkMode: ${Prefs().eInkMode},
          fontSize: ${bookStyle.fontSize},
          fontName: '${replaceSingleQuote(fontName)}',
          fontPath: '${replaceSingleQuote(fontPath)}',
          fontWeight: ${bookStyle.fontWeight},
          letterSpacing: ${bookStyle.letterSpacing},
          spacing: ${bookStyle.lineHeight},
          paragraphSpacing: ${bookStyle.paragraphSpacing},
          textIndent: ${bookStyle.indent},
          fontColor: '#$textColor',
          backgroundColor: '#$backgroundColor',
          topMargin: ${bookStyle.topMargin},
          bottomMargin: ${bookStyle.bottomMargin},
          sideMargin: ${bookStyle.sideMargin},
          justify: true,
          hyphenate: true,
          pageTurnStyle: '${Prefs().pageTurnStyle.name}',
          maxColumnCount: ${bookStyle.maxColumnCount},
      }
      let readingRules = {
        convertChineseMode: '${Prefs().readingRules.convertChineseMode.name}',
        bionicReadingMode: ${Prefs().readingRules.bionicReading},
      }

      window.loadBook()
  ''';

  await controller.evaluateJavascript(source: script);
}
