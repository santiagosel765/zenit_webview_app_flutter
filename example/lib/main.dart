import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:zenit_webview_sdk/zenit_webview_sdk.dart';

import 'config/zenit_build_config.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  static const Map<String, dynamic> _devDefaultFiltersFallback = {
    'PROMOTOR': 'ABIMAEL PÉREZ US',
  };

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
          child: Column(
            children: [
              if (effectiveConfig.hasMissingTokens)
                _MissingCredentialsWarning(
                  sdkTokenMissing: !effectiveConfig.isSdkTokenSet,
                  accessTokenMissing: !effectiveConfig.isAccessTokenSet,
                ),
              Expanded(
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
            ],
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

    final effectiveShowDevLogs =
        ZenitBuildConfig.showDevLogs || resolvedEnvironment.showDevLogs == true;

    final webUrlOverride = ZenitBuildConfig.webUrlOverride.trim();
    final baseUrlOverride = ZenitBuildConfig.baseUrlOverride.trim();
    final sdkTokenOverride = ZenitBuildConfig.sdkToken.trim();
    final accessTokenOverride = ZenitBuildConfig.accessToken.trim();
    final fallbackEnabled =
        ZenitBuildConfig.enableLocalFiltersFallback && effectiveShowDevLogs;

    final parsedFiltersResolution = _resolveDefaultFilters(
      rawJson: ZenitBuildConfig.defaultFiltersJson,
      debugEnabled: effectiveShowDevLogs,
      fallbackEnabled: fallbackEnabled,
    );

    final effectiveWebUrl =
        webUrlOverride.isNotEmpty ? Uri.parse(webUrlOverride) : resolvedEnvironment.parsedWebUrl;

    final effectiveBaseUrl =
        baseUrlOverride.isNotEmpty ? baseUrlOverride : resolvedEnvironment.baseUrl;

    final effectiveMapId = ZenitBuildConfig.mapIdOverride > 0
        ? ZenitBuildConfig.mapIdOverride
        : resolvedEnvironment.mapId;

    final effectiveDefaultFilters = parsedFiltersResolution.parsedFilters ??
        resolvedEnvironment.defaultFilters;

    final effectiveSdkToken =
        sdkTokenOverride.isNotEmpty ? sdkTokenOverride : resolvedEnvironment.sdkToken;

    final effectiveAccessToken =
        accessTokenOverride.isNotEmpty ? accessTokenOverride : resolvedEnvironment.accessToken;

    if (effectiveShowDevLogs &&
        (effectiveSdkToken?.isEmpty ?? true || effectiveAccessToken?.isEmpty ?? true)) {
      debugPrint(
        '⚠️ Configuración incompleta: '
        'sdkTokenSet=${effectiveSdkToken?.isNotEmpty ?? false}, '
        'accessTokenSet=${effectiveAccessToken?.isNotEmpty ?? false}. '
        'El mapa puede quedarse en loading si faltan credenciales.',
      );
    }

    return _EffectiveConfig(
      environmentKey: environmentKey,
      effectiveWebUrl: effectiveWebUrl,
      effectiveBaseUrl: effectiveBaseUrl,
      effectiveMapId: effectiveMapId,
      effectiveDefaultFilters: effectiveDefaultFilters,
      effectiveSdkToken: effectiveSdkToken,
      effectiveAccessToken: effectiveAccessToken,
      effectiveShowDevLogs: effectiveShowDevLogs,
      defaultFiltersRaw: parsedFiltersResolution.rawValue,
      defaultFiltersParseError: parsedFiltersResolution.parseError,
      defaultFiltersFallbackUsed: parsedFiltersResolution.usedFallback,
      defaultFiltersSource: parsedFiltersResolution.source,
    );
  }

  _DefaultFiltersResolution _resolveDefaultFilters({
    required String rawJson,
    required bool debugEnabled,
    required bool fallbackEnabled,
  }) {
    final rawValue = rawJson;
    final trimmed = rawValue.trim();

    if (debugEnabled) {
      debugPrint('ZENIT_DEFAULT_FILTERS raw="$rawValue"');
      debugPrint('ZENIT_DEFAULT_FILTERS trimmed="$trimmed"');
    }

    if (trimmed.isEmpty) {
      if (fallbackEnabled) {
        if (debugEnabled) {
          debugPrint(
            'ZENIT_DEFAULT_FILTERS vacío; aplicando fallback local de prueba: '
            '$_devDefaultFiltersFallback',
          );
        }
        return _DefaultFiltersResolution(
          rawValue: rawValue,
          parsedFilters: _devDefaultFiltersFallback,
          source: 'local-dev-fallback-empty',
          usedFallback: true,
        );
      }

      if (debugEnabled) {
        debugPrint('ZENIT_DEFAULT_FILTERS vacío; se mantiene config del environment.');
      }
      return _DefaultFiltersResolution(
        rawValue: rawValue,
        parsedFilters: null,
        source: 'environment-defaults',
      );
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        if (debugEnabled) {
          debugPrint('ZENIT_DEFAULT_FILTERS parseado correctamente: $decoded');
        }
        return _DefaultFiltersResolution(
          rawValue: rawValue,
          parsedFilters: decoded,
          source: 'dart-define',
        );
      }

      final parseError =
          'El valor debe ser un JSON object y llegó como ${decoded.runtimeType}.';
      if (debugEnabled) {
        debugPrint('ZENIT_DEFAULT_FILTERS inválido. raw="$rawValue". error=$parseError');
      }
      if (fallbackEnabled) {
        if (debugEnabled) {
          debugPrint(
            'Aplicando fallback local de prueba por tipo no soportado: '
            '$_devDefaultFiltersFallback',
          );
        }
        return _DefaultFiltersResolution(
          rawValue: rawValue,
          parsedFilters: _devDefaultFiltersFallback,
          parseError: parseError,
          source: 'local-dev-fallback-invalid',
          usedFallback: true,
        );
      }

      return _DefaultFiltersResolution(
        rawValue: rawValue,
        parsedFilters: null,
        parseError: parseError,
        source: 'environment-defaults',
      );
    } on FormatException catch (error) {
      if (debugEnabled) {
        debugPrint('ZENIT_DEFAULT_FILTERS JSON inválido. raw="$rawValue". error=$error');
      }
      if (fallbackEnabled) {
        if (debugEnabled) {
          debugPrint(
            'Aplicando fallback local de prueba por JSON inválido: '
            '$_devDefaultFiltersFallback',
          );
        }
        return _DefaultFiltersResolution(
          rawValue: rawValue,
          parsedFilters: _devDefaultFiltersFallback,
          parseError: '$error',
          source: 'local-dev-fallback-invalid-json',
          usedFallback: true,
        );
      }

      return _DefaultFiltersResolution(
        rawValue: rawValue,
        parsedFilters: null,
        parseError: '$error',
        source: 'environment-defaults',
      );
    }
  }

  void _debugLogEffectiveConfig(_EffectiveConfig config) {
    debugPrint('Zenit effective config (${config.environmentKey}):');
    debugPrint('  webUrl=${config.effectiveWebUrl}');
    debugPrint('  baseUrl=${config.effectiveBaseUrl}');
    debugPrint('  mapId=${config.effectiveMapId}');
    debugPrint('  defaultFiltersRaw=${config.defaultFiltersRaw}');
    debugPrint('  defaultFiltersFinal=${config.effectiveDefaultFilters}');
    debugPrint('  defaultFiltersSource=${config.defaultFiltersSource}');
    debugPrint('  defaultFiltersFallbackUsed=${config.defaultFiltersFallbackUsed}');
    if (config.defaultFiltersParseError != null) {
      debugPrint('  defaultFiltersParseError=${config.defaultFiltersParseError}');
    }
    debugPrint('  sdkTokenSet=${config.isSdkTokenSet}');
    debugPrint('  accessTokenSet=${config.isAccessTokenSet}');
    debugPrint('  sdkTokenLength=${config.effectiveSdkToken?.length ?? 0}');
    debugPrint('  accessTokenLength=${config.effectiveAccessToken?.length ?? 0}');
    debugPrint(
      '  enableLocalFiltersFallback=${ZenitBuildConfig.enableLocalFiltersFallback}',
    );
    debugPrint('  showDevLogs=${config.effectiveShowDevLogs}');
  }
}

class _MissingCredentialsWarning extends StatelessWidget {
  const _MissingCredentialsWarning({
    required this.sdkTokenMissing,
    required this.accessTokenMissing,
  });

  final bool sdkTokenMissing;
  final bool accessTokenMissing;

  @override
  Widget build(BuildContext context) {
    final missing = <String>[
      if (sdkTokenMissing) 'ZENIT_SDK_TOKEN',
      if (accessTokenMissing) 'ZENIT_ACCESS_TOKEN',
    ].join(', ');

    return Material(
      color: Colors.orange.shade100,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Configuración incompleta del example. Faltan credenciales: '
                '$missing. Revisa los --dart-define para evitar loading infinito.',
              ),
            ),
          ),
        ),
      ),
    );
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
    required this.defaultFiltersRaw,
    required this.defaultFiltersSource,
    required this.defaultFiltersFallbackUsed,
    this.defaultFiltersParseError,
  });

  final String environmentKey;
  final Uri effectiveWebUrl;
  final String effectiveBaseUrl;
  final int effectiveMapId;
  final Map<String, dynamic>? effectiveDefaultFilters;
  final String? effectiveSdkToken;
  final String? effectiveAccessToken;
  final bool effectiveShowDevLogs;
  final String defaultFiltersRaw;
  final String? defaultFiltersParseError;
  final bool defaultFiltersFallbackUsed;
  final String defaultFiltersSource;

  bool get isSdkTokenSet => (effectiveSdkToken ?? '').isNotEmpty;
  bool get isAccessTokenSet => (effectiveAccessToken ?? '').isNotEmpty;
  bool get hasMissingTokens => !isSdkTokenSet || !isAccessTokenSet;
}

class _DefaultFiltersResolution {
  const _DefaultFiltersResolution({
    required this.rawValue,
    required this.parsedFilters,
    required this.source,
    this.parseError,
    this.usedFallback = false,
  });

  final String rawValue;
  final Map<String, dynamic>? parsedFilters;
  final String? parseError;
  final bool usedFallback;
  final String source;
}
