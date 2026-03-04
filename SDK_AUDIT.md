# Auditoría técnica para migración a package publicable (pub.dev)

## Hallazgos

### 1) Mapa de archivos relevantes

- `lib/main.dart`
  - Contiene **toda la lógica funcional actual** de la app: arranque, widget principal, configuración del `WebViewController`, estado de UI (`loading/ready/error`), timeout, overlays de error/loading, panel de logs, bridge JS y modelos de runtime config.
  - Define el canal JS `ZenitNative` y el handler de mensajes entrantes (`_handleWebEvent`).
  - Implementa envíos Flutter -> Web con `runJavaScript` (`sendRuntimeConfig`, `setFilters`) a través de `ZenitBridge`.
- `lib/config/zenit_build_config.dart`
  - Configuración de entorno por `String.fromEnvironment` / `int.fromEnvironment` / `bool.fromEnvironment`.
  - Incluye: `webUrl`, `baseUrl`, `mapId`, `filterPromotor`, `sdkToken`, `accessToken`, `isDebug`, `showDevLogs`.
- `pubspec.yaml`
  - Proyecto tipado hoy como **app**, con `publish_to: 'none'`.
  - Dependencia principal funcional: `webview_flutter`.
- `android/app/src/main/AndroidManifest.xml`
  - Tiene `INTERNET` y `usesCleartextTraffic="true"`.
- `ios/Runner/Info.plist`
  - Configuración iOS por defecto de template Flutter; no se observa excepción ATS explícita.

> No se encontraron archivos separados adicionales para bridge/modelos/helpers: hoy están embebidos en `lib/main.dart`.

### 2) Inventario de features actuales

#### URLs que abre

- El WebView carga `ZenitBuildConfig.webUrl` con default `http://10.0.2.2:5173/`.
- Runtime config incluye `baseUrl` default `http://10.0.2.2:3200/api/v1`.

#### Mensajes que recibe Flutter desde WebView

Canal JS registrado:
- `ZenitNative`.

Formato esperado:
- JSON con `type`.

Tipos procesados:
- `console`: registra `level` y `args`.
- `event`: registra `name` y `detail`.
- `error`: registra `message`.
- fallback: guarda payload completo o texto plano si no es JSON.

Eventos web explícitamente escuchados por el bootstrap JS y enviados a Flutter:
- `zenit:runtime-applied`
- `zenit:filters-applied`
- `error`
- `unhandledrejection`

#### Mensajes que envía Flutter al WebView

Con `runJavaScript`:
- Inyección de bootstrap (`_bootstrapScript`) al finalizar carga.
- `sendRuntimeConfig(...)`:
  - setea `window.__ZENIT_RUNTIME_CONFIG__ = cfg`.
  - dispara `CustomEvent('zenit:runtime-config', { detail: cfg })`.
- `setFilters(...)`:
  - dispara `CustomEvent('zenit:set-filters', { detail: { filters, merge } })`.

#### Token/header/auth/runtime config

- Maneja tokens en runtime config (no por headers HTTP del request WebView):
  - `accessToken` (opcional, string no vacío)
  - `sdkToken` (opcional, string no vacío)
- También envía:
  - `baseUrl`
  - `mapId`
  - `defaultFilters`

#### Loading/errores/intercepción de navegación

- Estados UI: `loading`, `ready`, `error`.
- Timeout de carga principal: 25s, pasa a estado `error`.
- Errores de recursos:
  - main frame => overlay de error + botón retry.
  - subrecursos => log + overlay debug opcional + snackBar opcional.
- Intercepción navegación:
  - `onNavigationRequest` solo loguea y permite navegar (`NavigationDecision.navigate`).
- Back handling:
  - `WillPopScope` usa historial interno de WebView (`canGoBack/goBack`).

### 3) Inventario de dependencias

Dependencias en `pubspec.yaml`:
- `flutter` SDK
- `webview_flutter: ^4.10.0`
- `cupertino_icons: ^1.0.8` (solo UI)

Dev dependencies:
- `flutter_test`
- `flutter_lints`

Plugins/plataformas nativas relevantes:
- Android manifest ya habilita `INTERNET` y cleartext traffic.
- iOS no tiene ATS override explícito; si se usan URLs `http`, puede requerir configuración en `example/ios/Runner/Info.plist`.

### 4) Riesgos para pub.dev si se migra “tal cual”

1. **Estructura app-first**
   - Hoy todo está en `lib/main.dart`; para package debe existir librería reusable (`lib/<package>.dart` + `lib/src`).
2. **Config acoplada a compile-time env**
   - `ZenitBuildConfig` con `String.fromEnvironment` no debería ser obligatoria para consumidores del SDK.
3. **`publish_to: 'none'`**
   - Bloquea publicación.
4. **README/metadata de package incompletos**
   - Faltan docs de API, ejemplo de uso y hardening para `pub publish --dry-run`.
5. **Cleartext/URLs locales hardcodeadas por default**
   - Defaults tipo `10.0.2.2` sirven para demo, no para SDK productivo.
6. **API pública implícita/no versionada**
   - Canal `ZenitNative`, eventos `zenit:*` y payloads están solo en implementación interna; conviene formalizarlos en contratos documentados.

## Arquitectura propuesta

### Estructura final sugerida

```text
/lib
  zenit_webview_sdk.dart               # exports públicos
  /src
    zenit_webview_widget.dart          # widget reusable
    zenit_bridge.dart                  # bridge JS + cola pending
    zenit_runtime_config.dart          # modelo runtime
    zenit_callbacks.dart               # typedefs / clase de callbacks
    zenit_ui_state.dart                # enum/estado interno si aplica
    zenit_log_event.dart               # modelo opcional de logs/eventos
/example
  lib/main.dart                        # demo app (usa ZenitBuildConfig)
  lib/config/zenit_build_config.dart   # se mantiene sólo en example
```

### API pública propuesta del SDK

- `ZenitWebViewSdk` (`StatefulWidget`)
  - Params mínimos:
    - `Uri webUrl` (required)
    - `ZenitRuntimeConfig runtimeConfig` (required)
    - `bool enableLogs = false`
    - `Duration loadTimeout = const Duration(seconds: 25)`
    - `bool showDefaultLoading = true`
    - `bool showDefaultError = true`
    - `WidgetBuilder? loadingBuilder`
    - `Widget Function(BuildContext, Object error)? errorBuilder`
    - `NavigationDecision Function(NavigationRequest request)? onNavigationRequest`
    - `void Function(ZenitWebEvent event)? onWebEvent`
    - `void Function(WebResourceError error)? onWebResourceError`
    - `void Function(WebViewController controller)? onWebViewCreated`

- `ZenitRuntimeConfig`
  - `baseUrl`, `mapId`, `defaultFilters`, `accessToken?`, `sdkToken?`
  - `toJson()` (sin campos vacíos)

- `ZenitBridge` (público mínimo o interno con hooks)
  - Constantes formalizadas:
    - JS channel: `ZenitNative`
    - Eventos out: `zenit:runtime-config`, `zenit:set-filters`
    - Eventos in: `zenit:runtime-applied`, `zenit:filters-applied`

### Reparto SDK vs example

**SDK (`/lib`)**
- WebView reusable + bridge + modelos + callbacks + defaults seguros.

**Example (`/example`)**
- App host (`MaterialApp`, theming, overlays demo extendidos, dev logs panel demo).
- `ZenitBuildConfig` con `String.fromEnvironment`.
- Permisos/plist/manifests específicos para ejecutar demo local (`http://10.0.2.2`).

## Plan de implementación paso a paso

1. Crear API pública del package (`lib/zenit_webview_sdk.dart`) y mover clases de dominio (`ZenitRuntimeConfig`, bridge, callbacks) a `lib/src`.
2. Extraer `WebViewScreen` a widget reusable (`ZenitWebViewSdk`) eliminando dependencias de `ZenitBuildConfig`.
3. Convertir valores de config actuales en parámetros obligatorios/opcionales del widget.
4. Mantener comportamiento por defecto equivalente (timeout, overlays, queue de acciones pending, eventos JS).
5. Crear `example/` Flutter app y mover ahí `ZenitBuildConfig` + wiring actual.
6. Actualizar `pubspec.yaml`:
   - nombre package (`zenit_webview_sdk` recomendado)
   - remover `publish_to: 'none'`
   - completar `description`, `homepage`, `repository`, `issue_tracker`, `topics`.
7. Documentar contrato de bridge/eventos en README.
8. Ejecutar validación:
   - `flutter analyze`
   - `flutter test`
   - `flutter pub publish --dry-run`
9. Ajustar iOS/Android del `example` para HTTP local cuando aplique.

## Riesgos y mitigaciones

- **Riesgo:** romper integración web por cambiar nombres de eventos/canal.
  - **Mitigación:** mantener exactamente `ZenitNative`, `zenit:runtime-config`, `zenit:set-filters`, `zenit:runtime-applied`, `zenit:filters-applied`.
- **Riesgo:** comportamiento visual distinto (loading/error).
  - **Mitigación:** defaults equivalentes + builders opcionales.
- **Riesgo:** consumidores requieran headers HTTP en vez de runtime events.
  - **Mitigación:** documentar claramente que auth actual viaja en runtime config JS; evaluar feature futura para headers en `loadRequest`.
- **Riesgo:** incompatibilidad iOS con `http://` en demo.
  - **Mitigación:** configurar ATS en `example` si se usan endpoints no-HTTPS en desarrollo.

## Lista de cambios exactos recomendados (migración)

### Crear
- `lib/zenit_webview_sdk.dart`
- `lib/src/zenit_webview_widget.dart`
- `lib/src/zenit_bridge.dart`
- `lib/src/zenit_runtime_config.dart`
- `lib/src/zenit_callbacks.dart`
- `example/` app Flutter completa
- `CHANGELOG.md`
- `LICENSE` (si no existe)

### Mover/refactorizar
- Código de `lib/main.dart`:
  - Bridge/modelos/widget reusable -> `lib/src/...`
  - App shell (`main`, `MaterialApp`) -> `example/lib/main.dart`
- `lib/config/zenit_build_config.dart` -> `example/lib/config/zenit_build_config.dart`

### Eliminar/ajustar
- Eliminar `publish_to: 'none'` en `pubspec.yaml`.
- Reescribir README orientado a SDK (instalación, API, ejemplo, contrato JS bridge).

### Naming de package recomendado
- Opción 1 (más explícita): `zenit_webview_sdk` ✅
- Opción 2 (más amplia/futura): `zenit_sdk_flutter`

Recomendación: **`zenit_webview_sdk`** para reflejar scope real actual (WebView + bridge).

## Checklist para publicar en pub.dev

- [ ] `pubspec.yaml` con metadata completa y sin `publish_to: none`.
- [ ] API pública estable y documentada en `lib/zenit_webview_sdk.dart`.
- [ ] `README.md` con quickstart + callbacks + contrato de eventos.
- [ ] `LICENSE` válido.
- [ ] `CHANGELOG.md` con versión inicial.
- [ ] `example/` funcional y ejecutable.
- [ ] `flutter analyze` sin issues críticos.
- [ ] `flutter test` pasando.
- [ ] `flutter pub publish --dry-run` OK.
