# zenit_webview_sdk_example

Example app for `zenit_webview_sdk`.

The example resolves a base config from `ZENIT_ENVIRONMENT_KEY` and then applies optional `--dart-define` overrides.

## Priority rules

1. Explicit overrides from `--dart-define` (non-empty values) win.
2. If no override is provided, values from the environment registry are used.
3. Compatible with environment-only usage.

## Run with environment key only

```bash
flutter run -d <device> --dart-define=ZENIT_ENVIRONMENT_KEY=PROD_IT_01
```

## Run with overrides

```bash
flutter run -d <device> \
  --dart-define=ZENIT_ENVIRONMENT_KEY=PROD_IT_01 \
  --dart-define=ZENIT_MAP_ID=19 \
  --dart-define=ZENIT_DEFAULT_FILTERS={"PROMOTOR":"JHONY EDUARDO CHOC TOT"} \
  --dart-define=ZENIT_SHOW_DEV_LOGS=true
```

## Supported `dart-define` keys

- `ZENIT_ENVIRONMENT_KEY`
- `ZENIT_WEB_URL`
- `ZENIT_BASE_URL`
- `ZENIT_MAP_ID`
- `ZENIT_DEFAULT_FILTERS`
- `ZENIT_SDK_TOKEN`
- `ZENIT_ACCESS_TOKEN`
- `ZENIT_SHOW_DEV_LOGS`
