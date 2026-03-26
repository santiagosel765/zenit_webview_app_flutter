import 'zenit_runtime_config.dart';

class ZenitResolvedEnvironmentConfig {
  const ZenitResolvedEnvironmentConfig({
    required this.webUrl,
    required this.baseUrl,
    required this.mapId,
    this.defaultFilters,
    this.accessToken,
    this.sdkToken,
    this.showDevLogs,
  });

  final String webUrl;

  Uri get parsedWebUrl => Uri.parse(webUrl);
  final String baseUrl;
  final int mapId;
  final Map<String, dynamic>? defaultFilters;
  final String? accessToken;
  final String? sdkToken;
  final bool? showDevLogs;

  ZenitRuntimeConfig toRuntimeConfig() {
    return ZenitRuntimeConfig(
      baseUrl: baseUrl,
      mapId: mapId,
      defaultFilters: defaultFilters,
      accessToken: accessToken,
      sdkToken: sdkToken,
    );
  }
}
