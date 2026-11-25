/// 本地数据管理抽象（文档 #24 / #43 / #44）。
library;

/// 敏感数据存储：Token / Secret。
///
/// 业务代码只依赖该抽象，装配层决定使用哪种实现
/// （移动端 Keystore / Keychain，桌面端加密文件，测试内存实现）。
abstract interface class SecureStorage {
  /// 写入。
  Future<void> write(String key, String value);

  /// 读取。
  Future<String?> read(String key);

  /// 删除。
  Future<void> delete(String key);

  /// 清空。
  Future<void> clear();
}

/// 普通配置存储：服务器地址、语言、主题、UI 设置。
abstract interface class PreferencesStorage {
  /// 读取字符串。
  Future<String?> readString(String key);

  /// 写入字符串。
  Future<void> writeString(String key, String value);

  /// 读取字符串列表。
  Future<List<String>> readStringList(String key);

  /// 写入字符串列表。
  Future<void> writeStringList(String key, List<String> value);

  /// 删除单个键。
  Future<void> remove(String key);

  /// 清空全部。
  Future<void> clear();
}

/// 存储键常量，避免业务代码散落字符串。
abstract final class StorageKeys {
  /// 主题模式。
  static const String themeMode = 'appearance.theme_mode';

  /// 语言。
  static const String locale = 'appearance.locale';

  /// 已保存的服务端档案列表（JSON 数组）。
  static const String serverProfiles = 'server.profiles';

  /// 最近使用的服务端档案 ID。
  static const String activeServerId = 'server.active_id';

  /// 日志级别。
  static const String logLevel = 'diagnostics.log_level';

  /// 安全存储：访问令牌。
  static const String accessToken = 'auth.access_token';

  /// 安全存储：刷新令牌。
  static const String refreshToken = 'auth.refresh_token';

  /// 安全存储：访问令牌过期时间。
  static const String accessTokenExpiresAt = 'auth.access_token_expires_at';

  /// 安全存储：刷新令牌过期时间。
  static const String refreshTokenExpiresAt = 'auth.refresh_token_expires_at';

  /// 安全存储：当前用户（JSON）。
  static const String currentUser = 'auth.user';

  /// 安全存储：令牌所属服务端档案 ID。
  static const String sessionServerId = 'auth.server_id';

  /// 安全存储：已记住的登录用户名（「记住密码」开启时写入）。
  static const String rememberedUsername = 'auth.remembered_username';

  /// 安全存储：已记住的登录密码（「记住密码」开启时写入）。
  ///
  /// 只写入系统安全存储（Keystore / Keychain / 加密文件），
  /// 绝不进入普通配置文件。
  static const String rememberedPassword = 'auth.remembered_password';

  /// 普通配置：是否启用「记住密码」。
  static const String rememberPassword = 'auth.remember_password_enabled';

  /// 普通配置：小说阅读设置（JSON）。
  static const String novelReaderSettings = 'reader.novel.settings';

  /// 普通配置：漫画阅读设置（JSON）。
  static const String comicReaderSettings = 'reader.comic.settings';

  /// 普通配置：阅读进度索引（JSON 数组，按内容维度保存）。
  static const String readingProgress = 'reader.progress';
}
