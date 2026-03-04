import 'package:flutter_test/flutter_test.dart';
import 'package:zenit_webview_sdk/zenit_webview_sdk.dart';

void main() {
  test('ZenitRuntimeConfig.toJson removes empty optional fields', () {
    final config = ZenitRuntimeConfig(
      baseUrl: 'https://api.example.com/v1',
      mapId: 19,
      defaultFilters: const {'PROMOTOR': 'DEMO'},
      accessToken: '',
      sdkToken: null,
    );

    expect(config.toJson(), {
      'baseUrl': 'https://api.example.com/v1',
      'mapId': 19,
      'defaultFilters': const {'PROMOTOR': 'DEMO'},
    });
  });

  test('ZenitRuntimeConfig.toJson omits defaultFilters when null', () {
    final config = ZenitRuntimeConfig(
      baseUrl: 'https://api.example.com/v1',
      mapId: 19,
      defaultFilters: null,
    );

    expect(config.toJson(), {
      'baseUrl': 'https://api.example.com/v1',
      'mapId': 19,
    });
  });
}
