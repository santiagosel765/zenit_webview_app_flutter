import 'zenit_resolved_environment_config.dart';

const Map<String, ZenitResolvedEnvironmentConfig> zenitEnvironments = {
  'DEV_INNOVA_01': ZenitResolvedEnvironmentConfig(
    webUrl: 'http://10.0.2.2:5173/',
    baseUrl: 'http://10.0.2.2:3200/api/v1',
    mapId: 19,
    accessToken: '', 
    sdkToken: '',
    showDevLogs: true,
  ),
  'QA_IT_01': ZenitResolvedEnvironmentConfig(
    webUrl: 'https://qa.innova.genesisempresarial.com/zenit-playground/',
    baseUrl: 'https://qa.innova.genesisempresarial.com/zenit-api/api/v1',
    mapId: 19,
    accessToken: '', 
    sdkToken: '',
    showDevLogs: true,
  ),
  'PROD_IT_01': ZenitResolvedEnvironmentConfig(
    webUrl: 'https://innova.genesisempresarial.com/zenit-playground/',
    baseUrl: 'https://innova.genesisempresarial.com/zenit-api/api/v1',
    mapId: 19,
    accessToken: '', 
    sdkToken: '',
    showDevLogs: false,
  ),
};

ZenitResolvedEnvironmentConfig? resolveZenitEnvironment(String environmentKey) {
  return zenitEnvironments[environmentKey.trim()];
}
