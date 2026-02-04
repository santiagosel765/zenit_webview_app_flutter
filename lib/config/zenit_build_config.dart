class ZenitBuildConfig {
  static const String webUrl = String.fromEnvironment(
    'ZENIT_WEB_URL',
    defaultValue: 'http://10.0.2.2:5173/',
  );
  static const String baseUrl = String.fromEnvironment(
    'ZENIT_BASE_URL',
    defaultValue: 'http://10.0.2.2:3200/api/v1',
  );
  static const int mapId = int.fromEnvironment(
    'ZENIT_MAP_ID',
    defaultValue: 19,
  );
  static const String filterPromotor = String.fromEnvironment(
    'ZENIT_FILTER_PROMOTOR',
    defaultValue: 'PROMOTOR DEMO',
  );
  static const String? sdkToken =
      String.fromEnvironment('ZENIT_SDK_TOKEN', defaultValue: '');
  static const String? accessToken =
      String.fromEnvironment('ZENIT_ACCESS_TOKEN', defaultValue: '');
  static const bool isDebug = bool.fromEnvironment(
    'ZENIT_DEBUG',
    defaultValue: true,
  );
}
