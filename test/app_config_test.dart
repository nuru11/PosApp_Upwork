import 'package:flutter_test/flutter_test.dart';
import 'package:pointofsalesapp/core/config/app_config.dart';

void main() {
  test('uses one valid HTTPS URL for every platform', () {
    final uri = Uri.parse(AppConfig.webUrl);

    expect(uri.scheme, 'https');
    expect(uri.hasAuthority, isTrue);
    expect(AppConfig.allowedHost, uri.host);
  });
}
