# zenit_webview_sdk_example

Example app for `zenit_webview_sdk`.

## Run with environment key (recommended)

```bash
flutter run -d <device> --dart-define=ZENIT_ENVIRONMENT_KEY=PROD_IT_01
```

## Optional legacy overrides (migration only)

```bash
flutter run -d <device> \
  --dart-define=ZENIT_ENVIRONMENT_KEY=DEV_INNOVA_01 \
  --dart-define=ZENIT_WEB_URL=http://10.0.2.2:5173/ \
  --dart-define=ZENIT_BASE_URL=http://10.0.2.2:3200/api/v1 \
  --dart-define=ZENIT_MAP_ID=19
```
