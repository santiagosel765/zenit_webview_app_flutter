import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import 'zenit_runtime_config.dart';

class ZenitBridge {
  ZenitBridge({required WebViewController controller}) : _controller = controller;

  static const String jsChannelName = 'ZenitNative';

  final WebViewController _controller;
  bool _pageReady = false;
  bool _webReady = false;
  final List<Completer<void>> _webReadyWaiters = [];
  final List<Future<void> Function()> _pendingActions = [];

  Completer<void>? _runtimeAppliedCompleter;
  Completer<void>? _filtersAppliedCompleter;

  String? _lastRuntimeSignatureSent;
  String? _lastFiltersSignatureSent;
  int _runtimeDispatchCounter = 0;
  int _filtersDispatchCounter = 0;

  void onPageStarted() {
    _pageReady = false;
    _webReady = false;
    _pendingActions.clear();
    _runtimeAppliedCompleter = null;
    _filtersAppliedCompleter = null;
    _lastRuntimeSignatureSent = null;
    _lastFiltersSignatureSent = null;

    for (final waiter in _webReadyWaiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('WebView navigation restarted before web-ready.'));
      }
    }
    _webReadyWaiters.clear();
  }

  Future<void> onPageFinished() async {
    _pageReady = true;
    await _controller.runJavaScript(_bootstrapScript);
    await _probeWebReady();
  }

  Future<bool> waitForWebReady({
    Duration timeout = const Duration(seconds: 2),
    bool allowPageReadyFallback = true,
  }) async {
    if (_webReady) return true;

    await _probeWebReady();
    if (_webReady) return true;

    final waiter = Completer<void>();
    _webReadyWaiters.add(waiter);

    try {
      await waiter.future.timeout(timeout);
      return true;
    } on TimeoutException {
      if (allowPageReadyFallback && _pageReady) {
        _markWebReady(source: 'timeout-page-ready-fallback');
      }
      return false;
    }
  }

  BridgeDispatchResult sendRuntimeConfig(
    ZenitRuntimeConfig config, {
    required String signature,
  }) {
    if (_lastRuntimeSignatureSent == signature) {
      return BridgeDispatchResult.skipped(
        reason: 'runtime-config signature already dispatched for current page',
        signature: signature,
      );
    }

    final requestId = 'runtime-${++_runtimeDispatchCounter}';
    final payload = jsonEncode(config.toJson());
    _runtimeAppliedCompleter = Completer<void>();

    unawaited(_runWhenOperationalReady(() {
      return _controller.runJavaScript('''
(() => {
  const cfg = $payload;
  const meta = {
    requestId: '$requestId',
    signature: ${jsonEncode(signature)},
    sentAt: new Date().toISOString(),
  };
  window.__ZENIT_RUNTIME_CONFIG__ = cfg;
  window.__ZENIT_RUNTIME_CONFIG_META__ = meta;
  window.dispatchEvent(new CustomEvent('zenit:runtime-config', { detail: cfg }));
  window.dispatchEvent(new CustomEvent('zenit:runtime-config-sent', { detail: meta }));
})();
''');
    }));

    _lastRuntimeSignatureSent = signature;
    return BridgeDispatchResult.dispatched(requestId: requestId, signature: signature);
  }

  BridgeDispatchResult setFilters(
    Map<String, dynamic>? filters, {
    bool merge = false,
    required String signature,
  }) {
    if (_lastFiltersSignatureSent == signature) {
      return BridgeDispatchResult.skipped(
        reason: 'set-filters signature already dispatched for current page',
        signature: signature,
      );
    }

    final requestId = 'filters-${++_filtersDispatchCounter}';
    final payload = jsonEncode({'filters': filters, 'merge': merge});
    _filtersAppliedCompleter = Completer<void>();

    unawaited(_runWhenOperationalReady(() {
      return _controller.runJavaScript('''
(() => {
  const detail = $payload;
  const meta = {
    requestId: '$requestId',
    signature: ${jsonEncode(signature)},
    sentAt: new Date().toISOString(),
  };
  window.__ZENIT_FILTERS_CONFIG_META__ = meta;
  window.dispatchEvent(new CustomEvent('zenit:set-filters', { detail }));
  window.dispatchEvent(new CustomEvent('zenit:set-filters-sent', { detail: meta }));
})();
''');
    }));

    _lastFiltersSignatureSent = signature;
    return BridgeDispatchResult.dispatched(requestId: requestId, signature: signature);
  }

  void onWebMessage(Map<String, dynamic> decoded) {
    final type = decoded['type']?.toString();
    if (type != 'event') return;

    final name = decoded['name']?.toString();
    if (name == null) return;

    if (name == 'zenit:web-ready') {
      _markWebReady(source: 'web-event');
      return;
    }

    if (name == 'zenit:runtime-applied') {
      if (_runtimeAppliedCompleter != null && !_runtimeAppliedCompleter!.isCompleted) {
        _runtimeAppliedCompleter!.complete();
      }
      return;
    }

    if (name == 'zenit:filters-applied') {
      if (_filtersAppliedCompleter != null && !_filtersAppliedCompleter!.isCompleted) {
        _filtersAppliedCompleter!.complete();
      }
    }
  }

  Future<bool> waitForRuntimeAppliedAck({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final completer = _runtimeAppliedCompleter;
    if (completer == null) return false;

    try {
      await completer.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<bool> waitForFiltersAppliedAck({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final completer = _filtersAppliedCompleter;
    if (completer == null) return false;

    try {
      await completer.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  void _markWebReady({required String source}) {
    if (_webReady) return;
    _webReady = true;

    for (final waiter in _webReadyWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _webReadyWaiters.clear();

    unawaited(_flushPendingActions());

    unawaited(_controller.runJavaScript('''
(() => {
  window.__ZENIT_FLUTTER_READY_SOURCE__ = ${jsonEncode(source)};
})();
'''));
  }

  Future<void> _probeWebReady() async {
    if (!_pageReady || _webReady) return;

    try {
      final result = await _controller.runJavaScriptReturningResult('''
(() => {
  const isReady = Boolean(
    window.__ZENIT_WEB_READY__ ||
    window.__ZENIT_APP_READY__ ||
    (window.__ZENIT_NATIVE__ && window.__ZENIT_NATIVE__.webReady === true)
  );

  if (isReady) {
    window.dispatchEvent(new CustomEvent('zenit:web-ready', { detail: { source: 'probe-flags' } }));
  } else {
    window.dispatchEvent(new CustomEvent('zenit:flutter-ready-check'));
  }

  return isReady;
})();
''');

      if ('$result' == 'true' || '$result' == '1') {
        _markWebReady(source: 'probe-flags');
      }
    } catch (_) {
      // noop
    }
  }

  Future<void> _runWhenOperationalReady(Future<void> Function() action) async {
    if (_pageReady && _webReady) {
      await action();
      return;
    }

    _pendingActions.add(action);
  }

  Future<void> _flushPendingActions() async {
    if (!_pageReady || !_webReady || _pendingActions.isEmpty) return;

    final pending = List<Future<void> Function()>.from(_pendingActions);
    _pendingActions.clear();

    for (final action in pending) {
      await action();
    }
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
    webReady: false,
    post: (type, payload) => postMessage({ type, payload }),
    notifyWebReady: (detail) => {
      window.__ZENIT_NATIVE__.webReady = true;
      window.dispatchEvent(new CustomEvent('zenit:web-ready', { detail: detail || null }));
    },
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

  const forwardEvent = (eventName) => {
    window.addEventListener(eventName, (event) => {
      if (eventName === 'zenit:web-ready') {
        window.__ZENIT_NATIVE__.webReady = true;
      }

      postMessage({
        type: 'event',
        name: eventName,
        detail: event.detail ?? null,
      });
    });
  };

  ['zenit:web-ready', 'zenit:runtime-applied', 'zenit:filters-applied'].forEach(forwardEvent);

  window.addEventListener('zenit:flutter-ready-check', () => {
    const isReady = Boolean(window.__ZENIT_WEB_READY__ || window.__ZENIT_APP_READY__);
    if (isReady) {
      window.dispatchEvent(new CustomEvent('zenit:web-ready', { detail: { source: 'flutter-ready-check' } }));
    }
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

  postMessage({ type: 'event', name: 'zenit:bridge-ready', detail: { ts: new Date().toISOString() } });
})();
''';
}

class BridgeDispatchResult {
  const BridgeDispatchResult._({
    required this.dispatched,
    this.requestId,
    required this.signature,
    this.reason,
  });

  final bool dispatched;
  final String? requestId;
  final String signature;
  final String? reason;

  bool get skipped => !dispatched;

  factory BridgeDispatchResult.dispatched({
    required String requestId,
    required String signature,
  }) {
    return BridgeDispatchResult._(
      dispatched: true,
      requestId: requestId,
      signature: signature,
    );
  }

  factory BridgeDispatchResult.skipped({
    required String reason,
    required String signature,
  }) {
    return BridgeDispatchResult._(
      dispatched: false,
      signature: signature,
      reason: reason,
    );
  }
}
