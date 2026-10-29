import 'package:flutter_test/flutter_test.dart';

void main() {
  test('firebase dart-defines are empty by default in tests', () {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

    expect(apiKey, isEmpty);
    expect(appId, isEmpty);
    expect(senderId, isEmpty);
    expect(projectId, isEmpty);
  });
}