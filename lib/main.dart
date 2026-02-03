import 'dart:convert';

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
  int _progress = 0;
  bool _hasError = false;
  final TextEditingController _mapIdController =
      TextEditingController(text: '19');
  final TextEditingController _promotorController =
      TextEditingController(text: 'PROMOTOR DEMO');
  final List<String> _eventLogs = [];
  final String _webUrl = 'http://10.0.2.2:5173/';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ZenitBridge',
        onMessageReceived: (message) => _handleWebEvent(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) => setState(() => _progress = progress),
          onPageStarted: (_) => setState(() {
            _hasError = false;
            _progress = 0;
          }),
          onPageFinished: (_) async {
            setState(() => _progress = 100);
            await _injectRuntimeConfig();
          },
          onWebResourceError: (err) {
            debugPrint('WEBVIEW ERROR: code=${err.errorCode} '
                'type=${err.errorType} desc=${err.description} '
                'url=${err.url}');
            setState(() => _hasError = true);
          },
        ),
      )
      ..loadRequest(Uri.parse(_webUrl));
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
                              onPressed: () => _controller.reload(),
                              child: const Text('Reintentar'),
                            )
                          ],
                        ),
                      )
                    else
                      WebViewWidget(controller: _controller),
                    if (_progress < 100 && !_hasError)
                      LinearProgressIndicator(value: _progress / 100),
                  ],
                ),
              ),
              _ConfigPanel(
                mapIdController: _mapIdController,
                promotorController: _promotorController,
                logs: _eventLogs,
                onApplyFilters: _sendFilters,
                onClearFilters: _clearFilters,
                onSendRuntimeConfig: _injectRuntimeConfig,
                onReload: () => _controller.reload(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> get _runtimeConfig => {
        // TODO: Reemplazar por la baseUrl real según entorno.
        'baseUrl': 'https://api.dev.zenit.example.com',
        // TODO: No hardcodear tokens en producción.
        'sdkToken': 'DEMO_TOKEN_REEMPLAZAR',
        'mapId': _mapIdController.text.trim(),
        'defaultFilters': _buildFiltersPayload(),
      };

  Map<String, dynamic> _buildFiltersPayload() {
    final promotor = _promotorController.text.trim();
    if (promotor.isEmpty) {
      return {};
    }
    return {'PROMOTOR': promotor};
  }

  Future<void> _injectRuntimeConfig() async {
    final payload = jsonEncode(_runtimeConfig);
    await _controller.runJavaScript('''
window.__ZENIT_RUNTIME_CONFIG__ = $payload;
window.dispatchEvent(new CustomEvent('zenit:runtime-config', { detail: window.__ZENIT_RUNTIME_CONFIG__ }));
''');
    _appendLog('Flutter -> Web: runtime-config enviado');
  }

  Future<void> _sendFilters() async {
    final payload = jsonEncode(_buildFiltersPayload());
    await _controller.runJavaScript('''
window.dispatchEvent(new CustomEvent('zenit:set-filters', { detail: $payload }));
''');
    _appendLog('Flutter -> Web: filtros enviados');
  }

  Future<void> _clearFilters() async {
    await _controller.runJavaScript('''
window.dispatchEvent(new CustomEvent('zenit:clear-filters'));
window.dispatchEvent(new CustomEvent('zenit:set-filters', { detail: {} }));
''');
    _appendLog('Flutter -> Web: filtros limpiados');
  }

  void _handleWebEvent(String message) {
    try {
      final decoded = jsonDecode(message);
      _appendLog('Web -> Flutter: $decoded');
    } catch (_) {
      _appendLog('Web -> Flutter (texto): $message');
    }
  }

  void _appendLog(String entry) {
    setState(() {
      _eventLogs.insert(0, '${DateTime.now().toIso8601String()} $entry');
      if (_eventLogs.length > 50) {
        _eventLogs.removeLast();
      }
    });
  }

  @override
  void dispose() {
    _mapIdController.dispose();
    _promotorController.dispose();
    super.dispose();
  }
}

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.mapIdController,
    required this.promotorController,
    required this.logs,
    required this.onApplyFilters,
    required this.onClearFilters,
    required this.onSendRuntimeConfig,
    required this.onReload,
  });

  final TextEditingController mapIdController;
  final TextEditingController promotorController;
  final List<String> logs;
  final VoidCallback onApplyFilters;
  final VoidCallback onClearFilters;
  final VoidCallback onSendRuntimeConfig;
  final VoidCallback onReload;

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
            Row(
              children: [
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
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: promotorController,
                    decoration: const InputDecoration(
                      labelText: 'Filtro PROMOTOR',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: onSendRuntimeConfig,
                  child: const Text('Enviar config'),
                ),
                FilledButton(
                  onPressed: onApplyFilters,
                  child: const Text('Aplicar filtros'),
                ),
                OutlinedButton(
                  onPressed: onClearFilters,
                  child: const Text('Limpiar filtros'),
                ),
                TextButton(
                  onPressed: onReload,
                  child: const Text('Recargar web'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Eventos recibidos',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: logs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Sin eventos aún.'),
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
