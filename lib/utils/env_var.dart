class EnvVar {
  static const bool isAppStore =
      String.fromEnvironment('isAppStore', defaultValue: 'false') == 'true';

  static const bool isPlayStore =
      String.fromEnvironment('isPlayStore', defaultValue: 'false') == 'true';
  static const bool isFdroid =
      String.fromEnvironment('isFdroid', defaultValue: 'false') == 'true';
  static const bool isOhosStore =
      String.fromEnvironment('isOhosStore', defaultValue: 'false') == 'true';

  static bool get isStoreBuild => isAppStore || isPlayStore;

  static bool get showIapPlaceHolder => isOhosStore;

  static bool get enableCheckUpdate => false;
  static bool get enableInAppPurchase => false;

  static bool get showBeian => false;
  static bool get enableOpenAiConfig => true;
  static bool get enableAIFeature => !isOhosStore;
}
