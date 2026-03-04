# zenit_webview_sdk

Flutter SDK package to embed Zenit's web experience in a `WebView` while preserving the existing JavaScript bridge contract.

## Installation

```bash
flutter pub add zenit_webview_sdk
```

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:zenit_webview_sdk/zenit_webview_sdk.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ZenitWebViewSdk(
      webUrl: Uri.parse('https://your-web-app.example.com/'),
      runtimeConfig: ZenitRuntimeConfig(
        baseUrl: 'https://api.example.com/v1',
        mapId: 19,
        defaultFilters: const {'PROMOTOR': 'PROMOTOR DEMO'},
        accessToken: 'ACCESS_TOKEN',
        sdkToken: 'SDK_TOKEN',
      ),
      enableLogs: true,
      onWebEvent: (event) {
        debugPrint('web event type=${event.type} name=${event.name}');
      },
    );
  }
}
```

## Bridge contract (kept unchanged)

- JS channel: `ZenitNative`
- Events from Web: `zenit:runtime-applied`, `zenit:filters-applied`, `error`, `unhandledrejection`
- Events from Flutter: `zenit:runtime-config`, `zenit:set-filters`

## Example app

A runnable host app is available in [`example/`](example/).

Run it with:

```bash
cd example
flutter pub get
flutter run \
  --dart-define=ZENIT_WEB_URL=http://10.0.2.2:5173/ \
  --dart-define=ZENIT_BASE_URL=http://10.0.2.2:3200/api/v1 \
  --dart-define=ZENIT_MAP_ID=19 \
  --dart-define='ZENIT_DEFAULT_FILTERS={"PROMOTOR":"JHONY EDUARDO CHOC TOT"}'
```
