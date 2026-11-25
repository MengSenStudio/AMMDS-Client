import 'storage.dart';

/// 内存安全存储：测试、Web 与降级场景使用。
final class InMemorySecureStorage implements SecureStorage {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();
}

/// 内存普通配置存储：测试、Web 与降级场景使用。
final class InMemoryPreferencesStorage implements PreferencesStorage {
  final Map<String, Object?> _data = <String, Object?>{};

  @override
  Future<String?> readString(String key) async {
    final value = _data[key];
    return value is String ? value : null;
  }

  @override
  Future<void> writeString(String key, String value) async =>
      _data[key] = value;

  @override
  Future<List<String>> readStringList(String key) async {
    final value = _data[key];
    if (value is List) {
      return value.map((item) => '$item').toList(growable: false);
    }
    return const <String>[];
  }

  @override
  Future<void> writeStringList(String key, List<String> value) async =>
      _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();
}
