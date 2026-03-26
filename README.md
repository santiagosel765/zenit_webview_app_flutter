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

You can also inspect `zenitEnvironments` if needed.

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

Run it with:

```bash
cd example
flutter run -d <device> --dart-define=ZENIT_ENVIRONMENT_KEY=PROD_IT_01
```

Optional legacy overrides for local debugging are still available:

```bash
flutter run -d <device> \
  --dart-define=ZENIT_ENVIRONMENT_KEY=DEV_INNOVA_01 \
  --dart-define=ZENIT_WEB_URL=http://10.0.2.2:5173/ \
  --dart-define=ZENIT_BASE_URL=http://10.0.2.2:3200/api/v1 \
  --dart-define=ZENIT_MAP_ID=19
```
