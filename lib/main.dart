import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'config/zenit_build_config.dart';

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

  final bool _showSubresourceDebugOverlay = ZenitBuildConfig.isDebug;
  final bool _showSubresourceSnackBar = ZenitBuildConfig.isDebug;
  bool get _isDebug => ZenitBuildConfig.isDebug;

  String? _lastSubresourceError;
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
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _hasError = false;
              _progress = 0;
              _lastSubresourceError = null;
            });
            _bridge.onPageStarted();
          },
          onPageFinished: (_) async {
            if (!mounted) return;
            setState(() => _progress = 100);

            await _bridge.onPageFinished();
            await _sendRuntimeConfig();
            await _sendFilters();
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

            if (err.isForMainFrame == true) {
              _appendLog('WebView MAIN-FRAME error: $entry');
              if (!mounted) return;
              setState(() => _hasError = true);
              return;
            }

            _appendLog('WebView SUBRESOURCE error: $entry');

            if (!mounted) return;
            setState(() {
              _lastSubresourceError = entry;
            });

            if (_showSubresourceSnackBar) {
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
    final url = ZenitBuildConfig.webUrl.trim();
    if (url.isEmpty) {
      _appendLog('WebView: URL vacía, no se puede cargar.');
      return;
    }
    await _controller.loadRequest(Uri.parse(url));
  }

  Future<void> _reloadWebView() async {
    if (!mounted) return;
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
                    // ✅ CORREGIDO: el if dentro del children con coma
                    if (_hasError && _isDebug)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('No se pudo cargar la página'),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _reloadWebView,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),

                    // Siempre mostramos el webview; si querés ocultarlo cuando hay error,
                    // podés envolverlo con: if (!_hasError) WebViewWidget(...)
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
                            color: Colors.black.withAlpha(180),
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
              if (_isDebug) _DebugLogs(logs: _eventLogs),
            ],
          ),
        ),
      ),
    );
  }

  ZenitRuntimeConfig _buildRuntimeConfig() {
    return ZenitRuntimeConfig(
      baseUrl: ZenitBuildConfig.baseUrl,
      accessToken: ZenitBuildConfig.accessToken,
      sdkToken: ZenitBuildConfig.sdkToken,
      mapId: ZenitBuildConfig.mapId,
      defaultFilters: _buildFiltersPayload(),
    );
  }

  Map<String, dynamic> _buildFiltersPayload() {
    final promotor = ZenitBuildConfig.filterPromotor.trim();
    if (promotor.isEmpty) return {};
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
    if (!_isDebug) return;
    if (!mounted) return;

    setState(() {
      _eventLogs.insert(0, '${DateTime.now().toIso8601String()} $entry');
      if (_eventLogs.length > 80) _eventLogs.removeLast();
    });
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
  final String accessToken;
  final String sdkToken;
  final int mapId;
  final Map<String, dynamic> defaultFilters;

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{
      'baseUrl': baseUrl,
      'defaultFilters': defaultFilters,
      'mapId': mapId,
    };

    if (accessToken.isNotEmpty) payload['accessToken'] = accessToken;
    if (sdkToken.isNotEmpty) payload['sdkToken'] = sdkToken;

    return payload;
  }
}

class ZenitBridge {
  ZenitBridge({required WebViewController controller}) : _controller = controller;

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

class _DebugLogs extends StatelessWidget {
  const _DebugLogs({required this.logs});

  final List<String> logs;

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
              'Logs (DEV)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
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
