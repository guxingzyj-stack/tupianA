class AppEnv {
  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0',
  );

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const appToken = String.fromEnvironment(
    'APP_TOKEN',
    defaultValue: 'dev-token-change-me',
  );
}
