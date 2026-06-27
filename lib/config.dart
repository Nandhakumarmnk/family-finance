/// App-wide, build-time configuration.
///
/// Values can be overridden at build time with `--dart-define=KEY=value`
/// (the CI passes some of these), otherwise the defaults below are used.
class AppConfig {
  AppConfig._();

  /// One-tap download for the latest Android build. Points at the optimized
  /// release APK published by the "Build Android APK" GitHub Action.
  static const String appDownloadUrl = String.fromEnvironment(
    'APK_DOWNLOAD_URL',
    defaultValue:
        'https://github.com/Nandhakumarmnk/family-finance/releases/latest/download/app-release.apk',
  );

  /// Friendly product name used in shareable invite messages.
  static const String appName = 'Family Finance';
}
