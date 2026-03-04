import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import 'zenit_runtime_config.dart';

class ZenitBridge {
  ZenitBridge({required WebViewController controller}) : _controller = controller;

  static const String jsChannelName = 'ZenitNative';

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

  Future<void> setFilters(Map<String, dynamic>? filters, {bool merge = false}) async {
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
