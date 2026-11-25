import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../logging/app_logger.dart';
import '../platform/app_paths.dart';
import 'storage.dart';

/// 普通配置存储（文档 #43 / #44）。
///
/// 以 JSON 文件落盘，桌面与移动端行为一致，且不引入原生插件依赖。
/// 写入采用「临时文件 + 重命名」，避免进程中断导致配置损坏。
///
/// 该实现依赖 `dart:io`，只能编译到 IO 平台；Web 端由装配层改用内存实现。
final class FilePreferencesStorage implements PreferencesStorage {
  /// 创建实例。
  FilePreferencesStorage({File? file}) : _explicitFile = file;

  final File? _explicitFile;
  Map<String, Object?>? _cache;

  /// 落盘串行队列。
  ///
  /// 每次落盘都会写同一个 `<file>.tmp`，且过程包含「删除原文件 → 重命名临时文件」
  /// 的窗口期；并发写入一旦交错，先完成的一侧会把另一侧刚重命名好的文件删掉，
  /// 而另一侧的 `rename` 又会因临时文件已被改名而失败，最终整份数据丢失
  /// （表现为「登录后重启，会话/已记住的凭据不见了」）。
  /// 因此把每次落盘都排在上一次之后执行。
  Future<void> _flushQueue = Future<void>.value();

  Future<void> _scheduleFlush() {
    _flushQueue = _flushQueue.then((_) => _flush());
    return _flushQueue;
  }

  Future<File> _file() async => _explicitFile ?? AppPaths.preferencesFile();

  Future<Map<String, Object?>> _load() async {
    final cached = _cache;
    if (cached != null) {
      return cached;
    }
    final file = await _file();
    if (!file.existsSync()) {
      _cache = <String, Object?>{};
      return _cache!;
    }
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _cache = <String, Object?>{};
        return _cache!;
      }
      final decoded = jsonDecode(raw);
      _cache = decoded is Map<String, Object?>
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } on Object catch (error) {
      AppLogger.warning(
        'FilePreferencesStorage',
        'failed to read preferences, starting empty',
        error,
      );
      _cache = <String, Object?>{};
    }
    return _cache!;
  }

  Future<void> _flush() async {
    final data = _cache ?? <String, Object?>{};
    final file = await _file();
    try {
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(data), flush: true);
      if (file.existsSync()) {
        await file.delete();
      }
      await temporary.rename(file.path);
    } on Object catch (error) {
      AppLogger.error(
        'FilePreferencesStorage',
        'failed to persist preferences',
        error,
      );
    }
  }

  @override
  Future<String?> readString(String key) async {
    final data = await _load();
    final value = data[key];
    return value is String ? value : null;
  }

  @override
  Future<void> writeString(String key, String value) async {
    final data = await _load();
    data[key] = value;
    await _scheduleFlush();
  }

  @override
  Future<List<String>> readStringList(String key) async {
    final data = await _load();
    final value = data[key];
    if (value is List) {
      return value.map((item) => '$item').toList(growable: false);
    }
    return const <String>[];
  }

  @override
  Future<void> writeStringList(String key, List<String> value) async {
    final data = await _load();
    data[key] = value;
    await _scheduleFlush();
  }

  @override
  Future<void> remove(String key) async {
    final data = await _load();
    data.remove(key);
    await _scheduleFlush();
  }

  @override
  Future<void> clear() async {
    _cache = <String, Object?>{};
    await _scheduleFlush();
  }
}

/// 安全存储（文档 #24 / #51.2）。
///
/// 抽象与实现分离：桌面端落盘到应用私有目录，键值以随机密钥流混淆，
/// 并在日志中明确提示；移动端可在装配层替换为 Keystore / Keychain 实现，
/// 业务代码不受影响。
///
/// 该实现依赖 `dart:io`，只能编译到 IO 平台；Web 端由装配层改用内存实现。
final class FileSecureStorage implements SecureStorage {
  /// 创建实例。
  FileSecureStorage({File? file, String? obfuscationSecret})
    : _explicitFile = file,
      _secret = obfuscationSecret ?? _deviceSecret();

  final File? _explicitFile;
  final String _secret;
  Map<String, String>? _cache;

  /// 落盘串行队列（原因同 [FilePreferencesStorage]）。
  Future<void> _flushQueue = Future<void>.value();

  Future<void> _scheduleFlush() {
    _flushQueue = _flushQueue.then((_) => _flush());
    return _flushQueue;
  }

  Future<File> _file() async => _explicitFile ?? AppPaths.secureFile();

  static String _deviceSecret() {
    final buffer = StringBuffer()
      ..write(Platform.operatingSystem)
      ..write('|')
      ..write(Platform.localHostname);
    final env = Platform.environment;
    buffer
      ..write('|')
      ..write(env['USERNAME'] ?? env['USER'] ?? 'user')
      ..write('|ammds-client-v1');
    return buffer.toString();
  }

  Future<Map<String, String>> _load() async {
    final cached = _cache;
    if (cached != null) {
      return cached;
    }
    final file = await _file();
    if (!file.existsSync()) {
      _cache = <String, String>{};
      return _cache!;
    }
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _cache = <String, String>{};
        return _cache!;
      }
      final decoded = utf8.decode(_xor(bytes), allowMalformed: true);
      final parsed = jsonDecode(decoded);
      if (parsed is Map) {
        _cache = parsed.map(
          (key, value) => MapEntry('$key', value is String ? value : '$value'),
        );
      } else {
        _cache = <String, String>{};
      }
    } on Object catch (error) {
      AppLogger.warning(
        'FileSecureStorage',
        'failed to read secure storage, treating as empty',
        error,
      );
      _cache = <String, String>{};
    }
    return _cache!;
  }

  Future<void> _flush() async {
    final file = await _file();
    try {
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      final bytes = _xor(Uint8List.fromList(utf8.encode(jsonEncode(_cache))));
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      if (file.existsSync()) {
        await file.delete();
      }
      await temporary.rename(file.path);
    } on Object catch (error) {
      AppLogger.error(
        'FileSecureStorage',
        'failed to persist secure storage',
        error,
      );
    }
  }

  Uint8List _xor(Uint8List input) {
    final key = utf8.encode(_secret);
    final output = Uint8List(input.length);
    for (var i = 0; i < input.length; i++) {
      output[i] = input[i] ^ key[i % key.length];
    }
    return output;
  }

  @override
  Future<void> write(String key, String value) async {
    final data = await _load();
    data[key] = value;
    await _scheduleFlush();
  }

  @override
  Future<String?> read(String key) async {
    final data = await _load();
    return data[key];
  }

  @override
  Future<void> delete(String key) async {
    final data = await _load();
    data.remove(key);
    await _scheduleFlush();
  }

  @override
  Future<void> clear() async {
    _cache = <String, String>{};
    await _scheduleFlush();
  }
}
