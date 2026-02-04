import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zenit SDK Playground',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  late final ZenitBridge _bridge;
  int _progress = 0;
  bool _hasError = false;
  bool _showSubresourceDebugOverlay = false;
  bool _showSubresourceSnackBar = true;
  String? _lastSubresourceError;
  // Emulador Android: usar 10.0.2.2 para llegar al localhost del host.
  // Dispositivo físico: usar la IP LAN del host (ej. 192.168.x.x) y Vite con --host 0.0.0.0.
  final TextEditingController _webUrlController = TextEditingController(
    text: 'http://10.0.2.2:5173/',
  );
  final TextEditingController _baseUrlController = TextEditingController(
    text: 'http://10.0.2.2:3200/api/v1',
  );
  final TextEditingController _accessTokenController = TextEditingController();
  final TextEditingController _sdkTokenController = TextEditingController();
  final TextEditingController _mapIdController =
      TextEditingController(text: '19');
  final TextEditingController _promotorController =
      TextEditingController(text: 'PROMOTOR DEMO');
  final List<String> _eventLogs = [];

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ZenitNative',
        onMessageReceived: (message) => _handleWebEvent(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) => setState(() => _progress = progress),
          onPageStarted: (_) {
            setState(() {
              _hasError = false;
              _progress = 0;
              _lastSubresourceError = null;
            });
            _bridge.onPageStarted();
          },
          onPageFinished: (_) async {
            setState(() => _progress = 100);
            await _bridge.onPageFinished();
          },
          onNavigationRequest: (request) {
            debugPrint('WEBVIEW NAVIGATE: ${request.url}');
            _appendLog('WebView navigate: ${request.url}');
            return NavigationDecision.navigate;
          },
          onWebResourceError: (err) {
            final entry = 'code=${err.errorCode} type=${err.errorType} '
                'desc=${err.description} url=${err.url} '
                'isForMainFrame=${err.isForMainFrame}';
            debugPrint('WEBVIEW ERROR: $entry');
            if (err.isForMainFrame) {
              _appendLog('WebView MAIN-FRAME error: $entry');
              setState(() => _hasError = true);
              return;
            }
            _appendLog('WebView SUBRESOURCE error: $entry');
            setState(() {
              _lastSubresourceError = entry;
            });
            if (_showSubresourceSnackBar && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Error cargando datos (API), reintentando...'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      );

    _bridge = ZenitBridge(controller: _controller);

    _loadWebUrl();
  }

  Future<void> _loadWebUrl() async {
    final url = _webUrlController.text.trim();
    if (url.isEmpty) {
      _appendLog('WebView: URL vacía, no se puede cargar.');
      return;
    }
    await _controller.loadRequest(Uri.parse(url));
  }

  Future<void> _reloadWebView() async {
    setState(() {
      _hasError = false;
      _progress = 0;
      _lastSubresourceError = null;
    });
    await _loadWebUrl();
  }

  Future<bool> _onWillPop() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    if (_hasError)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('No se pudo cargar la página'),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _reloadWebView,
                              child: const Text('Reintentar'),
                            )
                          ],
                        ),
                      )
                    else
                      WebViewWidget(controller: _controller),
                    if (_progress < 100 && !_hasError)
                      LinearProgressIndicator(value: _progress / 100),
                    if (_showSubresourceDebugOverlay &&
                        !_hasError &&
                        _lastSubresourceError != null)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(maxWidth: 260),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _lastSubresourceError!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _ConfigPanel(
                webUrlController: _webUrlController,
                baseUrlController: _baseUrlController,
                accessTokenController: _accessTokenController,
                sdkTokenController: _sdkTokenController,
                mapIdController: _mapIdController,
                promotorController: _promotorController,
                logs: _eventLogs,
                onApplyFilters: _sendFilters,
                onClearFilters: _clearFilters,
                onSendRuntimeConfig: _sendRuntimeConfig,
                onReload: _reloadWebView,
              ),
            ],
          ),
        ),
      ),
    );
  }

  ZenitRuntimeConfig _buildRuntimeConfig() {
    final mapId = int.tryParse(_mapIdController.text.trim());
    return ZenitRuntimeConfig(
      baseUrl: _baseUrlController.text.trim(),
      accessToken: _accessTokenController.text.trim(),
      sdkToken: _sdkTokenController.text.trim(),
      mapId: mapId,
      defaultFilters: _buildFiltersPayload(),
    );
  }

  Map<String, dynamic> _buildFiltersPayload() {
    final promotor = _promotorController.text.trim();
    if (promotor.isEmpty) {
      return {};
    }
    return {'PROMOTOR': promotor};
  }

  Future<void> _sendRuntimeConfig() async {
    await _bridge.sendRuntimeConfig(_buildRuntimeConfig());
    _appendLog('Flutter -> Web: runtime-config enviado');
  }

  Future<void> _sendFilters() async {
    await _bridge.setFilters(_buildFiltersPayload());
    _appendLog('Flutter -> Web: filtros enviados');
  }

  Future<void> _clearFilters() async {
    await _bridge.clearFilters();
    _appendLog('Flutter -> Web: filtros limpiados');
  }

  void _handleWebEvent(String message) {
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final type = decoded['type']?.toString() ?? 'unknown';
      if (type == 'console') {
        final level = decoded['level']?.toString() ?? 'log';
        _appendLog('console.$level ${decoded['args']}');
        return;
      }
      if (type == 'event') {
        final name = decoded['name']?.toString() ?? 'event';
        _appendLog('Web event: $name detail=${decoded['detail']}');
        return;
      }
      if (type == 'error') {
        _appendLog('Web error: ${decoded['message']}');
        return;
      }
      _appendLog('Web -> Flutter: $decoded');
    } catch (_) {
      _appendLog('Web -> Flutter (texto): $message');
    }
  }

  void _appendLog(String entry) {
    setState(() {
      _eventLogs.insert(0, '${DateTime.now().toIso8601String()} $entry');
      if (_eventLogs.length > 80) {
        _eventLogs.removeLast();
      }
    });
  }

  @override
  void dispose() {
    _webUrlController.dispose();
    _baseUrlController.dispose();
    _accessTokenController.dispose();
    _sdkTokenController.dispose();
    _mapIdController.dispose();
    _promotorController.dispose();
    super.dispose();
  }
}

class ZenitRuntimeConfig {
  ZenitRuntimeConfig({
    required this.baseUrl,
    required this.accessToken,
    required this.sdkToken,
    required this.mapId,
    required this.defaultFilters,
  });

  final String baseUrl;
  final String? accessToken;
  final String? sdkToken;
  final int? mapId;
  final Map<String, dynamic> defaultFilters;

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{
      'baseUrl': baseUrl,
      'defaultFilters': defaultFilters,
    };
    if (accessToken != null && accessToken!.isNotEmpty) {
      payload['accessToken'] = accessToken;
    }
    if (sdkToken != null && sdkToken!.isNotEmpty) {
      payload['sdkToken'] = sdkToken;
    }
    if (mapId != null) {
      payload['mapId'] = mapId;
    }
    return payload;
  }
}

class ZenitBridge {
  ZenitBridge({required WebViewController controller})
      : _controller = controller;

  final WebViewController _controller;
  bool _pageReady = false;
  final List<Future<void> Function()> _pendingActions = [];

  void onPageStarted() {
    _pageReady = false;
    _pendingActions.clear();
  }

  Future<void> onPageFinished() async {
    _pageReady = true;
    await _controller.runJavaScript(_bootstrapScript);
    final pending = List<Future<void> Function()>.from(_pendingActions);
    _pendingActions.clear();
    for (final action in pending) {
      await action();
    }
  }

  Future<void> sendRuntimeConfig(ZenitRuntimeConfig config) async {
    final payload = jsonEncode(config.toJson());
    await _runWhenReady(() {
      return _controller.runJavaScript('''
(() => {
  const cfg = $payload;
  window.__ZENIT_RUNTIME_CONFIG__ = cfg;
  window.dispatchEvent(new CustomEvent('zenit:runtime-config', { detail: cfg }));
})();
''');
    });
  }

  Future<void> setFilters(Map<String, dynamic>? filters,
      {bool merge = false}) async {
    final payload = jsonEncode({'filters': filters, 'merge': merge});
    await _runWhenReady(() {
      return _controller.runJavaScript('''
(() => {
  const detail = $payload;
  window.dispatchEvent(new CustomEvent('zenit:set-filters', { detail }));
})();
''');
    });
  }

  Future<void> clearFilters() async {
    await setFilters(null);
  }

  Future<bool> ping() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        'window.__ZENIT_NATIVE__ && window.__ZENIT_NATIVE__.__bridgeReady',
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _runWhenReady(Future<void> Function() action) async {
    if (_pageReady) {
      await action();
      return;
    }
    _pendingActions.add(action);
  }

  static const String _bootstrapScript = '''
(() => {
  if (window.__ZENIT_NATIVE__ && window.__ZENIT_NATIVE__.__bridgeReady) {
    return;
  }

  const postMessage = (payload) => {
    try {
      if (window.ZenitNative && window.ZenitNative.postMessage) {
        window.ZenitNative.postMessage(JSON.stringify(payload));
      }
    } catch (err) {
      // noop
    }
  };

  window.__ZENIT_NATIVE__ = {
    __bridgeReady: true,
    post: (type, payload) => postMessage({ type, payload }),
  };

  const levels = ['log', 'info', 'warn', 'error'];
  levels.forEach((level) => {
    const original = console[level];
    console[level] = (...args) => {
      try {
        original.apply(console, args);
      } finally {
        postMessage({ type: 'console', level, args });
      }
    };
  });

  window.addEventListener('zenit:runtime-applied', (event) => {
    postMessage({
      type: 'event',
      name: 'zenit:runtime-applied',
      detail: event.detail ?? null,
    });
  });

  window.addEventListener('zenit:filters-applied', (event) => {
    postMessage({
      type: 'event',
      name: 'zenit:filters-applied',
      detail: event.detail ?? null,
    });
  });

  window.addEventListener('error', (event) => {
    postMessage({
      type: 'error',
      message: event.message,
      filename: event.filename,
      lineno: event.lineno,
      colno: event.colno,
      stack: event.error && event.error.stack ? event.error.stack : null,
    });
  });

  window.addEventListener('unhandledrejection', (event) => {
    postMessage({
      type: 'error',
      message: event.reason ? event.reason.toString() : 'unhandledrejection',
    });
  });
})();
''';
}

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.webUrlController,
    required this.baseUrlController,
    required this.accessTokenController,
    required this.sdkTokenController,
    required this.mapIdController,
    required this.promotorController,
    required this.logs,
    required this.onApplyFilters,
    required this.onClearFilters,
    required this.onSendRuntimeConfig,
    required this.onReload,
  });

  final TextEditingController webUrlController;
  final TextEditingController baseUrlController;
  final TextEditingController accessTokenController;
  final TextEditingController sdkTokenController;
  final TextEditingController mapIdController;
  final TextEditingController promotorController;
  final List<String> logs;
  final VoidCallback onApplyFilters;
  final VoidCallback onClearFilters;
  final VoidCallback onSendRuntimeConfig;
  final VoidCallback onReload;

  String _buildUrlHint() {
    if (!Platform.isAndroid) {
      return 'En desktop/iOS usa el host normal.';
    }
    return 'Emulador Android: usa 10.0.2.2. Dispositivo físico: usa la IP LAN del host (ej. 192.168.x.x) y Vite con --host 0.0.0.0.';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Panel de Configuración (DEV)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: webUrlController,
              decoration: const InputDecoration(
                labelText: 'Web URL (Vite dev server)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _buildUrlHint(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL (API)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: sdkTokenController,
                    decoration: const InputDecoration(
                      labelText: 'SDK Token',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: mapIdController,
                    decoration: const InputDecoration(
                      labelText: 'Map ID',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: accessTokenController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Access Token',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: promotorController,
              decoration: const InputDecoration(
                labelText: 'Filtro PROMOTOR',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: onSendRuntimeConfig,
                  child: const Text('Aplicar Config'),
                ),
                FilledButton(
                  onPressed: onApplyFilters,
                  child: const Text('Aplicar Filtro'),
                ),
                OutlinedButton(
                  onPressed: onClearFilters,
                  child: const Text('Limpiar Filtros'),
                ),
                TextButton(
                  onPressed: onReload,
                  child: const Text('Recargar Web'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Logs',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: logs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Sin logs aún.'),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: logs.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          logs[index],
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
