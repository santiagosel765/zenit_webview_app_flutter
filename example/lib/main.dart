import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:zenit_webview_sdk/zenit_webview_sdk.dart';

import 'config/zenit_build_config.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final defaultFilters = _parseDefaultFilters(ZenitBuildConfig.defaultFiltersJson);
    final runtimeConfig = ZenitRuntimeConfig(
      baseUrl: ZenitBuildConfig.baseUrl,
      mapId: ZenitBuildConfig.mapId,
      accessToken: ZenitBuildConfig.accessToken,
      sdkToken: ZenitBuildConfig.sdkToken,
      defaultFilters: defaultFilters,
    );

    return MaterialApp(
      title: 'Zenit SDK Playground',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: ZenitWebViewSdk(
            webUrl: Uri.parse(ZenitBuildConfig.webUrl),
            runtimeConfig: runtimeConfig,
            enableLogs: ZenitBuildConfig.showDevLogs,
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _parseDefaultFilters(String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) return null;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      debugPrint(
        'ZENIT_DEFAULT_FILTERS ignorado: el valor debe ser un JSON object.',
      );
      return null;
    } catch (_) {
      debugPrint('ZENIT_DEFAULT_FILTERS ignorado: JSON inválido.');
      return null;
    }
  }
}
