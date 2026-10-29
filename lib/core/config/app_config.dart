class AppConfig {
  const AppConfig._();

  static const webUrl = 'https://terminal.ragmcloud.app/';

  static String get allowedHost => Uri.parse(webUrl).host;
}
