import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppStorage {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'access_token';
  static const _userKey = 'user_json';

  static Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  static Future<String?> getToken() => _storage.read(key: _tokenKey);

  static Future<void> saveUser(String userJson) =>
      _storage.write(key: _userKey, value: userJson);

  static Future<String?> getUser() => _storage.read(key: _userKey);

  static Future<void> clear() => _storage.deleteAll();
}
