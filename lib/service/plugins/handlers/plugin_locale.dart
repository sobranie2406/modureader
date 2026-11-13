import 'dart:io';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/app_language.dart';
import 'package:flutter/widgets.dart';

/// Locale key used when a contribution has to be materialised once, outside a
/// widget build. The manifest keeps every locale variant, but the host data
/// structures (prompts, toolbar items) store a single localized label.
String currentPluginLocaleKey() {
  final manual = Prefs().locale;
  if (manual != null) return appLocaleKey(manual);
  try {
    return appLocaleKey(WidgetsBinding.instance.platformDispatcher.locale);
  } catch (_) {
    return Platform.localeName.replaceAll('_', '-');
  }
}
