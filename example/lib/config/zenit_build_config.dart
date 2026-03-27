class ZenitBuildConfig {
  static const String environmentKey = String.fromEnvironment(
    'ZENIT_ENVIRONMENT_KEY',
    defaultValue: 'DEV_INNOVA_01',
  );

  static const String webUrlOverride = String.fromEnvironment(
    'ZENIT_WEB_URL',
    defaultValue: '',
  );

  static const String baseUrlOverride = String.fromEnvironment(
    'ZENIT_BASE_URL',
    defaultValue: '',
  );

  static const int mapIdOverride = int.fromEnvironment(
    'ZENIT_MAP_ID',
    defaultValue: -1,
  );

  static const String defaultFiltersJson = String.fromEnvironment(
    'ZENIT_DEFAULT_FILTERS',
    defaultValue: '',
  );

  static const String sdkToken = String.fromEnvironment(
    'ZENIT_SDK_TOKEN',
    defaultValue: '',
  );

  static const String accessToken = String.fromEnvironment(
    'ZENIT_ACCESS_TOKEN',
    defaultValue: '',
  );

  static const bool showDevLogs = bool.fromEnvironment(
    'ZENIT_SHOW_DEV_LOGS',
    defaultValue: false,
  );

  static const bool enableLocalFiltersFallback = bool.fromEnvironment(
    'ZENIT_ENABLE_LOCAL_FILTERS_FALLBACK',
    defaultValue: false,
  );
}
