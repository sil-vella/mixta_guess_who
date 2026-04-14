// lib/config/config.dart

class Config {

  static const bool loggerOn = true;

  static const String appTitle = "Mixta's Guess Who";

  // API URL
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://default.api.url',
  );
  // AdMob IDs
  static const String admobsTopBanner = String.fromEnvironment(
    'ADMOBS_TOP_BANNER01',
    defaultValue: '',
  );
  // AdMob IDs
  static const String admobsBottomBanner = String.fromEnvironment(
    'ADMOBS_BOTTOM_BANNER01',
    defaultValue: '',
  );

  static const String admobsInterstitial01 = String.fromEnvironment(
    'ADMOBS_INTERSTITIAL01',
    defaultValue: '',
  );

  static const String admobsRewarded01 = String.fromEnvironment(
    'ADMOBS_REWARDED01',
    defaultValue: '',
  );
}