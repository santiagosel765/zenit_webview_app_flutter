import 'dart:convert';

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

  String signature({String? environmentKey}) {
    final stablePayload = _sortJsonLike(toJson());
    final payloadAsString = jsonEncode(stablePayload);
    final env = (environmentKey ?? '').trim();
    if (env.isEmpty) return payloadAsString;
    return '$env|$payloadAsString';
  }

  Object? _sortJsonLike(Object? value) {
    if (value is Map) {
      final sortedEntries =
          value.entries.toList()
            ..sort(
              (a, b) => a.key.toString().compareTo(b.key.toString()),
            );
      return {
        for (final entry in sortedEntries) entry.key.toString(): _sortJsonLike(entry.value),
      };
    }

    if (value is List) {
      return value.map(_sortJsonLike).toList(growable: false);
    }

    return value;
  }
}
