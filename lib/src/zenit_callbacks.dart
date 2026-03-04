import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ZenitWebEvent {
  const ZenitWebEvent({
    required this.type,
    this.level,
    this.args,
    this.name,
    this.detail,
    this.message,
    this.raw,
  });

  final String type;
  final String? level;
  final Object? args;
  final String? name;
  final Object? detail;
  final String? message;
  final Object? raw;

  factory ZenitWebEvent.text(String message) {
    return ZenitWebEvent(type: 'text', message: message, raw: message);
  }
}

typedef ZenitWebEventHandler = void Function(ZenitWebEvent event);
typedef ZenitWebResourceErrorHandler = void Function(WebResourceError error);
typedef ZenitWebViewCreatedHandler = void Function(WebViewController controller);
typedef ZenitNavigationRequestHandler = NavigationDecision Function(
  NavigationRequest request,
);

typedef ZenitLoadingBuilder = WidgetBuilder;
typedef ZenitErrorBuilder = Widget Function(BuildContext context, Object error);

class ZenitCallbacks {
  const ZenitCallbacks({
    this.onNavigationRequest,
    this.onWebEvent,
    this.onWebResourceError,
    this.onWebViewCreated,
  });

  final ZenitNavigationRequestHandler? onNavigationRequest;
  final ZenitWebEventHandler? onWebEvent;
  final ZenitWebResourceErrorHandler? onWebResourceError;
  final ZenitWebViewCreatedHandler? onWebViewCreated;
}
