import 'dart:io';

class RegisterConnection {
  const RegisterConnection();

  Future<bool> canReach(String url) async {
    if (await _probe(url, 'HEAD')) return true;
    return _probe(url, 'GET');
  }

  Future<bool> _probe(String url, String method) async {
    final client = HttpClient();
    try {
      final request = await client
          .openUrl(method, Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      await response.drain<void>();
      return response.statusCode > 0;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
