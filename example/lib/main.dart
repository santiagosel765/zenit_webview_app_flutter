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

    final hasLegacyOverrides =
        ZenitBuildConfig.webUrlOverride.trim().isNotEmpty &&
        ZenitBuildConfig.baseUrlOverride.trim().isNotEmpty &&
        ZenitBuildConfig.mapIdOverride > 0;

    final sdkWidget = hasLegacyOverrides
        ? ZenitWebViewSdk(
            webUrl: Uri.parse(ZenitBuildConfig.webUrlOverride),
            runtimeConfig: ZenitRuntimeConfig(
              baseUrl: ZenitBuildConfig.baseUrlOverride,
              mapId: ZenitBuildConfig.mapIdOverride,
              accessToken: ZenitBuildConfig.accessToken,
              sdkToken: ZenitBuildConfig.sdkToken,
              defaultFilters: defaultFilters,
            ),
            enableLogs: ZenitBuildConfig.showDevLogs,
          )
        : ZenitWebViewSdk(
            environmentKey: ZenitBuildConfig.environmentKey,
            enableLogs: ZenitBuildConfig.showDevLogs,
          );

    return MaterialApp(
      title: 'Zenit SDK Playground',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: sdkWidget,
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
