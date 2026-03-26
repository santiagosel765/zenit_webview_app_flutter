import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:zenit_webview_sdk/zenit_webview_sdk.dart';

import 'config/zenit_build_config.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final effectiveConfig = _resolveEffectiveConfig();

    if (effectiveConfig.effectiveShowDevLogs) {
      _debugLogEffectiveConfig(effectiveConfig);
    }

    return MaterialApp(
      title: 'Zenit SDK Playground',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: ZenitWebViewSdk(
            webUrl: effectiveConfig.effectiveWebUrl,
            runtimeConfig: ZenitRuntimeConfig(
              baseUrl: effectiveConfig.effectiveBaseUrl,
              mapId: effectiveConfig.effectiveMapId,
              defaultFilters: effectiveConfig.effectiveDefaultFilters,
              accessToken: effectiveConfig.effectiveAccessToken,
              sdkToken: effectiveConfig.effectiveSdkToken,
            ),
            enableLogs: effectiveConfig.effectiveShowDevLogs,
          ),
        ),
      ),
    );
  }

  _EffectiveConfig _resolveEffectiveConfig() {
    final environmentKey = ZenitBuildConfig.environmentKey.trim();
    final resolvedEnvironment = zenitEnvironments[environmentKey];

    if (resolvedEnvironment == null) {
      final availableKeys = zenitEnvironments.keys.join(', ');
      throw ArgumentError.value(
        environmentKey,
        'ZENIT_ENVIRONMENT_KEY',
        'No existe en el registry. Valores válidos: $availableKeys',
      );
    }

    final webUrlOverride = ZenitBuildConfig.webUrlOverride.trim();
    final baseUrlOverride = ZenitBuildConfig.baseUrlOverride.trim();
    final sdkTokenOverride = ZenitBuildConfig.sdkToken.trim();
    final accessTokenOverride = ZenitBuildConfig.accessToken.trim();

    final parsedFiltersOverride = _parseDefaultFilters(
      ZenitBuildConfig.defaultFiltersJson,
      debugEnabled: ZenitBuildConfig.showDevLogs || resolvedEnvironment.showDevLogs == true,
    );

    final effectiveWebUrl =
        webUrlOverride.isNotEmpty ? Uri.parse(webUrlOverride) : resolvedEnvironment.parsedWebUrl;

    final effectiveBaseUrl =
        baseUrlOverride.isNotEmpty ? baseUrlOverride : resolvedEnvironment.baseUrl;

    final effectiveMapId =
        ZenitBuildConfig.mapIdOverride > 0 ? ZenitBuildConfig.mapIdOverride : resolvedEnvironment.mapId;

    final effectiveDefaultFilters = parsedFiltersOverride ?? resolvedEnvironment.defaultFilters;

    final effectiveSdkToken =
        sdkTokenOverride.isNotEmpty ? sdkTokenOverride : resolvedEnvironment.sdkToken;

    final effectiveAccessToken =
        accessTokenOverride.isNotEmpty ? accessTokenOverride : resolvedEnvironment.accessToken;

    final effectiveShowDevLogs = ZenitBuildConfig.showDevLogs || resolvedEnvironment.showDevLogs == true;

    return _EffectiveConfig(
      environmentKey: environmentKey,
      effectiveWebUrl: effectiveWebUrl,
      effectiveBaseUrl: effectiveBaseUrl,
      effectiveMapId: effectiveMapId,
      effectiveDefaultFilters: effectiveDefaultFilters,
      effectiveSdkToken: effectiveSdkToken,
      effectiveAccessToken: effectiveAccessToken,
      effectiveShowDevLogs: effectiveShowDevLogs,
    );
  }

  Map<String, dynamic>? _parseDefaultFilters(
    String rawJson, {
    required bool debugEnabled,
  }) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) return null;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (debugEnabled) {
        debugPrint(
          'ZENIT_DEFAULT_FILTERS ignorado: el valor debe ser un JSON object.',
        );
      }
      return null;
    } catch (_) {
      if (debugEnabled) {
        debugPrint('ZENIT_DEFAULT_FILTERS ignorado: JSON inválido.');
      }
      return null;
    }
  }

  void _debugLogEffectiveConfig(_EffectiveConfig config) {
    debugPrint('Zenit effective config (${config.environmentKey}):');
    debugPrint('  webUrl=${config.effectiveWebUrl}');
    debugPrint('  baseUrl=${config.effectiveBaseUrl}');
    debugPrint('  mapId=${config.effectiveMapId}');
    debugPrint('  defaultFilters=${config.effectiveDefaultFilters}');
    debugPrint('  sdkTokenSet=${(config.effectiveSdkToken ?? '').isNotEmpty}');
    debugPrint('  accessTokenSet=${(config.effectiveAccessToken ?? '').isNotEmpty}');
    debugPrint('  showDevLogs=${config.effectiveShowDevLogs}');
  }
}

class _EffectiveConfig {
  const _EffectiveConfig({
    required this.environmentKey,
    required this.effectiveWebUrl,
    required this.effectiveBaseUrl,
    required this.effectiveMapId,
    required this.effectiveDefaultFilters,
    required this.effectiveSdkToken,
    required this.effectiveAccessToken,
    required this.effectiveShowDevLogs,
  });

  final String environmentKey;
  final Uri effectiveWebUrl;
  final String effectiveBaseUrl;
  final int effectiveMapId;
  final Map<String, dynamic>? effectiveDefaultFilters;
  final String? effectiveSdkToken;
  final String? effectiveAccessToken;
  final bool effectiveShowDevLogs;
}
