# zenit_webview_sdk

Flutter SDK package to embed Zenit's web experience in a `WebView` while preserving the existing JavaScript bridge contract.

## Installation

```bash
flutter pub add zenit_webview_sdk
```

## Usage (recommended)

The recommended integration is environment-based. The integrator sends only an `environmentKey` and the SDK resolves `webUrl`, `baseUrl`, and `mapId` internally from the registry.

```dart
import 'package:flutter/material.dart';
import 'package:zenit_webview_sdk/zenit_webview_sdk.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ZenitWebViewSdk(
      environmentKey: 'PROD_IT_01',
      onWebEvent: (event) {
        debugPrint('web event type=${event.type} name=${event.name}');
      },
    );
  }
}
```

## Environment registry

The package includes a centralized registry with the supported keys:

- `DEV_INNOVA_01`
- `QA_IT_01`
- `PROD_IT_01`

You can inspect `zenitEnvironments` if needed.

## Legacy mode (transitional)

`webUrl` and `runtimeConfig` are still supported as fallback during migration, but `webUrl` is deprecated and `environmentKey` should be preferred in all new integrations.

```dart
ZenitWebViewSdk(
  webUrl: Uri.parse('https://your-web-app.example.com/'),
  runtimeConfig: ZenitRuntimeConfig(
    baseUrl: 'https://api.example.com/v1',
    mapId: 19,
  ),
)
```

If `environmentKey` is provided, it has priority and legacy parameters are ignored.

## Bridge contract (kept unchanged)

- JS channel: `ZenitNative`
- Events from Web: `zenit:runtime-applied`, `zenit:filters-applied`, `error`, `unhandledrejection`
- Events from Flutter: `zenit:runtime-config`, `zenit:set-filters`

## Example app

A runnable host app is available in [`example/`](example/).

Run it with environment only:

```bash
cd example
flutter run -d <device> --dart-define=ZENIT_ENVIRONMENT_KEY=PROD_IT_01
```

Run it with optional overrides (priority over registry values):

```bash
flutter run -d <device> \
  --dart-define=ZENIT_ENVIRONMENT_KEY=PROD_IT_01 \
  --dart-define=ZENIT_MAP_ID=19 \
  --dart-define=ZENIT_DEFAULT_FILTERS={"PROMOTOR":"LUIS ALFREDO CABRERA CAMAJÁ"} \
  --dart-define=ZENIT_SHOW_DEV_LOGS=true
```

Supported example overrides:

- `ZENIT_WEB_URL`
- `ZENIT_BASE_URL`
- `ZENIT_MAP_ID`
- `ZENIT_DEFAULT_FILTERS`
- `ZENIT_SDK_TOKEN`
- `ZENIT_ACCESS_TOKEN`
- `ZENIT_SHOW_DEV_LOGS`
