class ZenitRuntimeConfig {
  ZenitRuntimeConfig({
    required this.baseUrl,
    required this.mapId,
    this.defaultFilters,
    this.accessToken,
    this.sdkToken,
  });

  final String baseUrl;
  final int mapId;
  final Map<String, dynamic>? defaultFilters;
  final String? accessToken;
  final String? sdkToken;

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{
      'baseUrl': baseUrl,
      if (defaultFilters != null) 'defaultFilters': defaultFilters,
      'mapId': mapId,
    };

    if (accessToken != null && accessToken!.isNotEmpty) {
      payload['accessToken'] = accessToken;
    }
    if (sdkToken != null && sdkToken!.isNotEmpty) payload['sdkToken'] = sdkToken;

    payload.removeWhere((key, value) {
      if (value == null) return true;
      if (value is String) return value.trim().isEmpty;
      if (value is Map) return value.isEmpty;
      return false;
    });

    return payload;
  }
}
