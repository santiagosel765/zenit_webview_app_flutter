# zenit_webview_app

A new Flutter project.

## Web (web-react) configuración local

Si estás usando un frontend web (por ejemplo `web-react`) con Vite dentro de un
emulador Android, se recomienda apuntar el `VITE_ZENIT_BASE_URL` directamente
al backend (por ejemplo `http://10.0.2.2:3200/api/v1`) en lugar de depender del
proxy `/api`. Esto ayuda a evitar errores `ERR_CONTENT_LENGTH_MISMATCH` en el
WebView. Si decides mantener el proxy, considera aumentar `timeout` y
`proxyTimeout` y remover el header `content-length` en la respuesta del proxy.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
