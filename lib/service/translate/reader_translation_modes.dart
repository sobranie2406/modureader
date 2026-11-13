import 'package:flutter/foundation.dart';
import 'package:modu_reader/enums/translation_mode.dart';

/// Two independent controls for one text surface. Starting another translation
/// replaces the displayed translation; merely opening its menu changes nothing.
class ReaderTranslationModes {
  final language = ValueNotifier(TranslationModeEnum.off);
  final classical = ValueNotifier(TranslationModeEnum.off);

  void update(TranslationModeEnum mode, {required bool isClassical}) {
    language.value = isClassical ? TranslationModeEnum.off : mode;
    classical.value = isClassical ? mode : TranslationModeEnum.off;
  }

  void dispose() {
    language.dispose();
    classical.dispose();
  }
}
