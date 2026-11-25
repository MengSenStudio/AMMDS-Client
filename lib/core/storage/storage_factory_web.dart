import 'storage.dart';
import 'storage_impl_memory.dart';

export 'storage_impl_memory.dart';

/// Web 端存储装配。
///
/// 浏览器可用的持久化能力（`localStorage` / IndexedDB）需要额外依赖或
/// `dart:html`，为避免引入新依赖，Web 端暂时使用内存实现：
/// **刷新页面后需要重新登录、重新选择服务端**，对端到端测试场景足够。
PreferencesStorage createPreferencesStorage() => InMemoryPreferencesStorage();

/// Web 端安全存储装配（内存实现）。
SecureStorage createSecureStorage() => InMemorySecureStorage();
