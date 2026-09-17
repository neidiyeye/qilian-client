import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 用户主动选择“记住账号密码”后，两个字段均保存在系统钥匙串。
/// 不使用 SharedPreferences 保存密码，避免明文落入普通配置文件。
class SavedLoginCredentials {
  const SavedLoginCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

abstract interface class LoginCredentialStorage {
  Future<SavedLoginCredentials?> read();

  Future<void> save(String username, String password);

  Future<void> clear();
}

final class SecureLoginCredentialStorage implements LoginCredentialStorage {
  const SecureLoginCredentialStorage();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _usernameKey = 'qilian_saved_login_username';
  static const String _passwordKey = 'qilian_saved_login_password';

  @override
  Future<SavedLoginCredentials?> read() async {
    final values = await Future.wait([
      _storage.read(key: _usernameKey),
      _storage.read(key: _passwordKey),
    ]);
    final username = values[0];
    final password = values[1];
    if (username == null || username.isEmpty || password == null) return null;
    return SavedLoginCredentials(username: username, password: password);
  }

  @override
  Future<void> save(String username, String password) => Future.wait([
    _storage.write(key: _usernameKey, value: username.trim()),
    _storage.write(key: _passwordKey, value: password),
  ]);

  @override
  Future<void> clear() => Future.wait([
    _storage.delete(key: _usernameKey),
    _storage.delete(key: _passwordKey),
  ]);
}
