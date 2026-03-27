# Auditoría técnica: Flutter SDK + WebView Bridge (runtime-config / filtros)

Fecha: 2026-03-27
Repositorio: `zenit_webview_app_flutter`

## Objetivo
Determinar con evidencia si el problema de “no se pintan features en el mapa” puede originarse en:
- SDK Flutter
- bridge Flutter → WebView
- timing de envío de `runtime-config`
- serialización/entrega de `defaultFilters`

> Alcance: auditoría; **sin implementar fixes**.

## Flujo técnico observado (end-to-end)

1) Resolución de ambiente
- `ZenitWebViewSdk` prioriza `environmentKey` sobre parámetros legacy (`webUrl`/`runtimeConfig`).
- `environmentKey` se resuelve en `zenitEnvironments` por clave exacta tras `trim()`.
- Si no existe clave, lanza `ArgumentError`.

2) Construcción de runtime config
- Si hay `environmentKey`, usa `resolved.toRuntimeConfig()`.
- `ZenitRuntimeConfig.toJson()` incluye `baseUrl`, `mapId`, opcionales (`defaultFilters`, `accessToken`, `sdkToken`) y elimina vacíos/null.

3) Overrides en host app (example)
- `example` resuelve config efectiva combinando registry + `--dart-define`.
- Prioridad de overrides:
  - `ZENIT_WEB_URL`, `ZENIT_BASE_URL`, `ZENIT_MAP_ID`
  - `ZENIT_DEFAULT_FILTERS` (JSON) si parsea a `Map<String, dynamic>`
  - `ZENIT_SDK_TOKEN`, `ZENIT_ACCESS_TOKEN`
- Si `ZENIT_DEFAULT_FILTERS` es inválido/no objeto, se ignora silenciosamente (solo log en debug).

4) Lifecycle WebView / envío de eventos
- `onPageStarted`: limpia estado y cola pending del bridge.
- `onPageFinished`:
  1. marca UI `ready`
  2. ejecuta `bridge.onPageFinished()` (inyecta bootstrap JS)
  3. envía `runtime-config`
  4. envía `set-filters`

5) Bridge JS y eventos
- `sendRuntimeConfig` serializa con `jsonEncode` y ejecuta JS:
  - `window.__ZENIT_RUNTIME_CONFIG__ = cfg`
  - `window.dispatchEvent(new CustomEvent('zenit:runtime-config', { detail: cfg }))`
- `setFilters` dispara `zenit:set-filters` con `{ filters, merge }`.
- Bootstrap engancha `console.*`, `error`, `unhandledrejection`, y reenvía eventos `zenit:runtime-applied` y `zenit:filters-applied` vía `ZenitNative.postMessage`.

## Hallazgos

### H1. El SDK Flutter sí serializa correctamente el payload JSON (fortaleza)
- Se usa `jsonEncode(config.toJson())`, evitando concatenación manual peligrosa.
- Esto preserva caracteres Unicode (tildes/espacios) en cadenas JSON válidas.

### H2. Existe duplicidad funcional de filtros (riesgo de orden/efecto colateral)
- `defaultFilters` viajan dentro de `runtime-config`.
- Inmediatamente después, Flutter vuelve a enviar filtros por `zenit:set-filters`.
- Si el web SDK procesa ambos caminos en momentos distintos, puede producir estado intermedio o sobreescrituras no deterministas.

### H3. No hay handshake explícito de “web listener ready” (riesgo real de timing)
- El gating del bridge es `_pageReady` basado en `onPageFinished` del WebView, no en señal real del app web.
- No hay evento de readiness desde web confirmado por Flutter antes de despachar `runtime-config`.
- En apps SPA, `onPageFinished` puede ocurrir antes de que módulos JS terminen de registrar listeners.

### H4. Confirmación observada es parcial (puede dar falso positivo)
- Flutter considera éxito al ejecutar `runJavaScript` sin error.
- Ver `zenit:filters-applied` en logs prueba que *algún* flujo de filtros se aplicó, pero no demuestra que:
  - el `runtime-config` correcto gobernó la carga de features
  - el orden runtime→filtros fue el esperado
  - no hubo una primera señal perdida

### H5. Posibilidad de reenvíos por ciclo de navegación
- `onPageFinished` ejecuta siempre bootstrap + envíos.
- Si hay redirects/recargas parciales, puede haber envíos múltiples (no idempotencia explícita en Flutter).

### H6. Riesgo de pérdida silenciosa en parse de overrides (host example)
- `ZENIT_DEFAULT_FILTERS` inválido se ignora y cae a `null`/registry.
- En ejecución sin logs dev, esto puede pasar desapercibido y aparentar que “se enviaron filtros” cuando no eran los esperados.

## Evaluación específica solicitada

### 1) ¿`defaultFilters` viaja como objeto correcto?
Sí, cuando entra como `Map<String, dynamic>`; viaja como objeto JSON en runtime y en `set-filters`.

### 2) ¿Escapes/comillas raras?
En Flutter bridge no se observan problemas de escape (usa `jsonEncode`). El mayor riesgo está en el valor que llega a `ZENIT_DEFAULT_FILTERS` desde shell/PowerShell, antes del parse.

### 3) ¿Tildes/espacios pueden romper comparación?
No en la serialización Flutter. Sí podrían afectar matching del lado backend/web si la comparación no normaliza acentos/espacios, pero eso excede este repo.

### 4) ¿`onPageFinished` es suficiente?
No es garantía fuerte de readiness de listeners de la app web. Es suficiente para “document loaded”, no para “SDK web listo”.

### 5) ¿Hay retry/handshake/ack robusto?
- Retry del envío de runtime/filtros: no.
- Handshake real web-ready: no.
- Ack fuerte de recepción y procesamiento completo: parcial (solo eventos/logs que pueden no cubrir orden completo).

### 6) ¿Bridge despacha al DOM correcto?
Sí, usa `window.dispatchEvent(...)` sobre el documento actual del WebView. No hay evidencia de target incorrecto.

## Conclusión (clasificación)

**Opción C**: *“El SDK Flutter entrega bien parte del flujo, pero hay factores que pueden contribuir al fallo junto con el SDK Web”.*

Razonamiento:
- Descartado un bug obvio de serialización JSON en Flutter.
- Persisten riesgos reales de timing/orden (sin handshake), doble vía de filtros y confirmación parcial.
- Con los síntomas reportados (base map carga, filtros-applied aparece, sin features), es plausible un problema combinado Flutter timing + lógica web/backend de aplicación de runtime/filtros.

## Riesgos de confiabilidad vigentes
- Carrera entre `onPageFinished` y registro de listeners web.
- Doble fuente de verdad para filtros (`runtime-config.defaultFilters` y `zenit:set-filters`).
- Falta de correlación/ack transaccional (ej. configVersion/requestId).
- Parse fallido de `--dart-define` sin fail-fast.

## Recomendaciones (sin implementar aún)
1. Incorporar handshake explícito web-ready antes de enviar `runtime-config`.
2. Definir contrato de idempotencia/orden (runtime primero, luego filtros, con versionado).
3. Evitar duplicidad de filtros o formalizar precedencia inequívoca.
4. Añadir ACK estructurado desde web con hash del payload recibido.
5. Endurecer parse de `ZENIT_DEFAULT_FILTERS` en host: opción fail-fast en debug/qa.
6. Añadir trazas correlacionadas (requestId/timestamps) para reconstruir secuencia exacta.
