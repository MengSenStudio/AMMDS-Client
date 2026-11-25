import 'storage.dart';

/// 已记住的登录凭据（文档 #43：敏感配置只进安全存储）。
final class RememberedCredentials {
  /// 创建凭据。
  const RememberedCredentials({
    required this.username,
    required this.password,
  });

  /// 用户名。
  final String username;

  /// 密码（明文，仅从安全存储读出后用于预填登录表单）。
  final String password;

  /// 是否为空。
  bool get isEmpty => username.isEmpty && password.isEmpty;

  @override
  String toString() => 'RememberedCredentials($username, password: ***)';
}

/// 「记住密码」凭据存取。
///
/// 与 [SessionStore] 的区别：会话存的是令牌，本类存的是**用户主动勾选**后
/// 由用户自己决定保存的登录凭据，用于下次打开时预填表单。
///
/// 安全约定：
/// * 用户名与密码只写入 [SecureStorage]（Keystore / Keychain / 加密文件）；
/// * 普通配置里只保存一个布尔开关，便于在不读取密码的前提下判断是否需要预填；
/// * 关闭「记住密码」时立即删除安全存储中的凭据。
final class CredentialStore {
  /// 创建实例。
  CredentialStore({
    required this.secureStorage,
    required this.preferencesStorage,
  });

  /// 安全存储。
  final SecureStorage secureStorage;

  /// 普通配置存储（只保存开关）。
  final PreferencesStorage preferencesStorage;

  /// 是否启用了「记住密码」。
  Future<bool> isEnabled() async =>
      await preferencesStorage.readString(StorageKeys.rememberPassword) ==
      'true';

  /// 保存凭据并打开开关。
  Future<void> save(RememberedCredentials credentials) async {
    await secureStorage.write(
      StorageKeys.rememberedUsername,
      credentials.username,
    );
    await secureStorage.write(
      StorageKeys.rememberedPassword,
      credentials.password,
    );
    await preferencesStorage.writeString(StorageKeys.rememberPassword, 'true');
  }

  /// 读取凭据；未启用或不存在时返回 null。
  Future<RememberedCredentials?> read() async {
    if (!await isEnabled()) {
      return null;
    }
    final username = await secureStorage.read(StorageKeys.rememberedUsername);
    final password = await secureStorage.read(StorageKeys.rememberedPassword);
    if ((username == null || username.isEmpty) &&
        (password == null || password.isEmpty)) {
      return null;
    }
    return RememberedCredentials(
      username: username ?? '',
      password: password ?? '',
    );
  }

  /// 清除凭据并关闭开关。
  Future<void> clear() async {
    await secureStorage.delete(StorageKeys.rememberedUsername);
    await secureStorage.delete(StorageKeys.rememberedPassword);
    await preferencesStorage.remove(StorageKeys.rememberPassword);
  }
}
