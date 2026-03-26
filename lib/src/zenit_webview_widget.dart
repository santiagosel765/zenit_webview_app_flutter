import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'zenit_bridge.dart';
import 'zenit_environment_registry.dart';
import 'zenit_resolved_environment_config.dart';
import 'zenit_callbacks.dart';
import 'zenit_log_event.dart';
import 'zenit_runtime_config.dart';
import 'zenit_ui_state.dart';

class ZenitWebViewSdk extends StatefulWidget {
  const ZenitWebViewSdk({
    this.environmentKey,
    @Deprecated(
      'Legacy mode only. Prefer environmentKey so the SDK resolves URLs internally.',
    )
    this.webUrl,
    this.runtimeConfig,
    super.key,
    this.enableLogs,
    this.loadTimeout = const Duration(seconds: 25),
    this.showDefaultLoading = true,
    this.showDefaultError = true,
    this.loadingBuilder,
    this.errorBuilder,
    this.onNavigationRequest,
    this.onWebEvent,
    this.onWebResourceError,
    this.onWebViewCreated,
  });

  final String? environmentKey;
  @Deprecated(
    'Legacy mode only. Prefer environmentKey so the SDK resolves URLs internally.',
  )
  final Uri? webUrl;
  final ZenitRuntimeConfig? runtimeConfig;
  final bool? enableLogs;
  final Duration loadTimeout;
  final bool showDefaultLoading;
  final bool showDefaultError;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext, Object error)? errorBuilder;
  final NavigationDecision Function(NavigationRequest request)? onNavigationRequest;
  final void Function(ZenitWebEvent event)? onWebEvent;
  final void Function(WebResourceError error)? onWebResourceError;
  final void Function(WebViewController controller)? onWebViewCreated;


  ZenitResolvedEnvironmentConfig? get _resolvedEnvironment {
    final key = environmentKey;
    if (key == null || key.trim().isEmpty) return null;

    final resolved = resolveZenitEnvironment(key);
    if (resolved == null) {
      throw ArgumentError.value(
        key,
        'environmentKey',
        'No existe una configuración registrada para este environmentKey.',
      );
    }
    return resolved;
  }

  Uri get effectiveWebUrl {
    final resolved = _resolvedEnvironment;
    if (resolved != null) return resolved.parsedWebUrl;

    if (webUrl != null) return webUrl!;

    throw ArgumentError(
      'Debes enviar environmentKey o webUrl (legacy) para inicializar ZenitWebViewSdk.',
    );
  }

  ZenitRuntimeConfig get effectiveRuntimeConfig {
    final resolved = _resolvedEnvironment;
    if (resolved != null) return resolved.toRuntimeConfig();

    if (runtimeConfig != null) return runtimeConfig!;

    throw ArgumentError(
      'Debes enviar environmentKey o runtimeConfig (legacy) para inicializar ZenitWebViewSdk.',
    );
  }

  bool get effectiveEnableLogs {
    final resolved = _resolvedEnvironment;
    return enableLogs ?? resolved?.showDevLogs ?? false;
  }

  @override
  State<ZenitWebViewSdk> createState() => _ZenitWebViewSdkState();
}

class _ZenitWebViewSdkState extends State<ZenitWebViewSdk> {
  late final WebViewController _controller;
  late final ZenitBridge _bridge;

  final List<ZenitLogEvent> _eventLogs = [];

  ZenitUiState _uiState = ZenitUiState.loading;
  String? _uiErrorMessage;
  String? _lastSubresourceError;
  Timer? _loadTimeoutTimer;

  @override
  void initState() {
    super.initState();

    final PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        ZenitBridge.jsChannelName,
        onMessageReceived: (message) => _handleWebEvent(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (_) {
            if (!mounted) return;
            if (_uiState != ZenitUiState.loading) {
              setState(() => _uiState = ZenitUiState.loading);
            }
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _uiState = ZenitUiState.loading;
              _uiErrorMessage = null;
              _lastSubresourceError = null;
            });
            _startLoadTimeout();
            _bridge.onPageStarted();
          },
          onPageFinished: (_) async {
            if (!mounted) return;
            _cancelLoadTimeout();
            setState(() => _uiState = ZenitUiState.ready);

            await _bridge.onPageFinished();
            await _sendRuntimeConfig();
            await _sendFilters();
          },
          onNavigationRequest: (request) {
            _appendLog('WebView navigate: ${request.url}');
            return widget.onNavigationRequest?.call(request) ?? NavigationDecision.navigate;
          },
          onWebResourceError: (err) {
            widget.onWebResourceError?.call(err);
            final entry = 'code=${err.errorCode} type=${err.errorType} '
                'desc=${err.description} url=${err.url} '
                'isForMainFrame=${err.isForMainFrame}';

            if (err.isForMainFrame == true) {
              _appendLog('WebView MAIN-FRAME error: $entry');
              if (!mounted) return;
              _cancelLoadTimeout();
              setState(() {
                _uiState = ZenitUiState.error;
                _uiErrorMessage = '($entry) No se pudo cargar el WebView principal.';
              });
              return;
            }

            _appendLog('WebView SUBRESOURCE error: $entry');

            if (!mounted) return;
            setState(() {
              _lastSubresourceError = entry;
            });

            if (widget.effectiveEnableLogs) {
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
    widget.onWebViewCreated?.call(_controller);
    unawaited(_configureControllerAndLoad());
  }

  Future<void> _configureControllerAndLoad() async {
    if (Platform.isAndroid) {
      AndroidWebViewController.enableDebugging(true);

      final platformController = _controller.platform;
      if (platformController is AndroidWebViewController) {
        await platformController.setMediaPlaybackRequiresUserGesture(false);
      }

      await _controller.clearCache();
      await _controller.clearLocalStorage();
    }

    await _loadWebUrl();
  }

  Future<void> _loadWebUrl() async {
    await _controller.loadRequest(widget.effectiveWebUrl);
  }

  Future<void> _reloadWebView() async {
    if (!mounted) return;
    setState(() {
      _uiState = ZenitUiState.loading;
      _uiErrorMessage = null;
      _lastSubresourceError = null;
    });
    _startLoadTimeout();
    await _controller.reload();
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
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (widget.effectiveEnableLogs && _uiState != ZenitUiState.error && _lastSubresourceError != null)
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
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                if (_uiState == ZenitUiState.loading)
                  _buildLoading(context),
                if (_uiState == ZenitUiState.error)
                  _buildError(context),
              ],
            ),
          ),
          if (widget.effectiveEnableLogs) _DebugLogs(logs: _eventLogs),
        ],
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    if (widget.loadingBuilder != null) return widget.loadingBuilder!(context);
    if (!widget.showDefaultLoading) return const SizedBox.shrink();
    return const _WebViewLoadingOverlay();
  }

  Widget _buildError(BuildContext context) {
    final error = _uiErrorMessage ?? 'No se pudo cargar el WebView.';
    if (widget.errorBuilder != null) return widget.errorBuilder!(context, error);
    if (!widget.showDefaultError) return const SizedBox.shrink();
    return _WebViewErrorOverlay(
      message: _uiErrorMessage,
      onRetry: _reloadWebView,
    );
  }

  Future<void> _sendRuntimeConfig() async {
    await _bridge.sendRuntimeConfig(widget.effectiveRuntimeConfig);

    final defaultFilters = widget.effectiveRuntimeConfig.defaultFilters;
    if (defaultFilters != null && defaultFilters.isNotEmpty) {
      _appendLog('Flutter -> Web: runtime-config enviado con defaultFilters=$defaultFilters');
      return;
    }

    _appendLog('Flutter -> Web: runtime-config enviado');
  }

  Future<void> _sendFilters() async {
    await _bridge.setFilters(widget.effectiveRuntimeConfig.defaultFilters);
    _appendLog('Flutter -> Web: filtros enviados');
  }

  void _handleWebEvent(String message) {
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final type = decoded['type']?.toString() ?? 'unknown';
      late final ZenitWebEvent event;

      if (type == 'console') {
        final level = decoded['level']?.toString() ?? 'log';
        event = ZenitWebEvent(
          type: type,
          level: level,
          args: decoded['args'],
          raw: decoded,
        );
        _appendLog('console.$level ${decoded['args']}');
        widget.onWebEvent?.call(event);
        return;
      }

      if (type == 'event') {
        final name = decoded['name']?.toString() ?? 'event';
        event = ZenitWebEvent(
          type: type,
          name: name,
          detail: decoded['detail'],
          raw: decoded,
        );
        _appendLog('Web event: $name detail=${decoded['detail']}');
        widget.onWebEvent?.call(event);
        return;
      }

      if (type == 'error') {
        event = ZenitWebEvent(
          type: type,
          message: decoded['message']?.toString(),
          raw: decoded,
        );
        _appendLog('Web error: ${decoded['message']}');
        widget.onWebEvent?.call(event);
        return;
      }

      event = ZenitWebEvent(type: type, raw: decoded);
      _appendLog('Web -> Flutter: $decoded');
      widget.onWebEvent?.call(event);
    } catch (_) {
      _appendLog('Web -> Flutter (texto): $message');
      widget.onWebEvent?.call(ZenitWebEvent.text(message));
    }
  }

  void _appendLog(String entry) {
    if (!mounted) return;

    setState(() {
      _eventLogs.insert(0, ZenitLogEvent(timestamp: DateTime.now(), message: entry));
      if (_eventLogs.length > 80) _eventLogs.removeLast();
    });
  }

  void _startLoadTimeout() {
    _cancelLoadTimeout();
    _loadTimeoutTimer = Timer(widget.loadTimeout, () {
      if (!mounted) return;
      if (_uiState == ZenitUiState.ready) return;
      setState(() {
        _uiState = ZenitUiState.error;
        _uiErrorMessage = 'Tiempo de espera agotado cargando el WebView.';
      });
    });
  }

  void _cancelLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
  }

  @override
  void dispose() {
    _cancelLoadTimeout();
    super.dispose();
  }
}

class _DebugLogs extends StatelessWidget {
  const _DebugLogs({required this.logs});

  final List<ZenitLogEvent> logs;

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
            Text('Logs (DEV)', style: Theme.of(context).textTheme.titleMedium),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(logs[index].toString(), style: const TextStyle(fontSize: 12)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebViewLoadingOverlay extends StatelessWidget {
  const _WebViewLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(80),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Cargando mapa…', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Esto puede tardar unos segundos',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _WebViewErrorOverlay extends StatelessWidget {
  const _WebViewErrorOverlay({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(80),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No se pudo cargar el mapa',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      message!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
