import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

import '../logging/app_logger.dart';

/// 应用数据目录解析。
///
/// 桌面平台使用系统约定的数据目录；Android / iOS 通过 `path_provider`
/// 获取沙盒目录（移动端没有任何可写环境变量，必须由插件向系统查询）。
/// 任何一步失败都会继续尝试下一个候选目录，最终兜底到系统临时目录，
/// 保证存储层始终可用（离线能力不因目录不可用而失效）。
abstract final class AppPaths {
  static Directory? _supportDirectory;

  /// 应用私有支持目录（配置、缓存根目录）。
  static Future<Directory> supportDirectory() async {
    final cached = _supportDirectory;
    if (cached != null) {
      return cached;
    }
    final candidates = <Directory?>[
      await _fromPathProvider(),
      _desktopSupportDirectory(),
      _fallbackDirectory(),
    ];
    for (final directory in candidates) {
      if (directory == null) {
        continue;
      }
      try {
        if (!directory.existsSync()) {
          directory.createSync(recursive: true);
        }
        _supportDirectory = directory;
        return directory;
      } on Object catch (error) {
        AppLogger.warning(
          'AppPaths',
          'cannot use directory ${directory.path}',
          error,
        );
      }
    }
    // 全部候选目录不可用时的最后兜底：系统临时目录同样可写，
    // 存储层退化为「临时可用」而不是直接抛异常让上层登录 / 发现流程失败。
    final fallback = Directory.systemTemp.createTempSync('ammds_client');
    _supportDirectory = fallback;
    return fallback;
  }

  /// 配置文件路径。
  static Future<File> preferencesFile() async {
    final directory = await supportDirectory();
    return File('${directory.path}${Platform.pathSeparator}preferences.json');
  }

  /// 安全存储文件路径。
  static Future<File> secureFile() async {
    final directory = await supportDirectory();
    return File('${directory.path}${Platform.pathSeparator}secure.bin');
  }

  /// 缓存目录。
  static Future<Directory> cacheDirectory() async {
    final directory = await supportDirectory();
    final cache = Directory('${directory.path}${Platform.pathSeparator}cache');
    if (!cache.existsSync()) {
      cache.createSync(recursive: true);
    }
    return cache;
  }

  /// 重置缓存（测试使用）。
  @visibleForTesting
  static void reset() => _supportDirectory = null;

  static Future<Directory?> _fromPathProvider() async {
    if (kIsWeb) {
      return null;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }
    try {
      return await path_provider.getApplicationSupportDirectory();
    } on Object catch (error) {
      AppLogger.debug('AppPaths', 'path_provider unavailable: $error');
      return null;
    }
  }

  static Directory? _desktopSupportDirectory() {
    final appFolder = 'AMMDS Client';
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return Directory('$appData\\$appFolder');
      }
      return null;
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home/Library/Application Support/$appFolder');
      }
      return null;
    }
    if (Platform.isLinux) {
      final xdg = Platform.environment['XDG_DATA_HOME'];
      if (xdg != null && xdg.isNotEmpty) {
        return Directory('$xdg/ammds-client');
      }
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home/.local/share/ammds-client');
      }
      return null;
    }
    return null;
  }

  static Directory? _fallbackDirectory() =>
      Directory('${Directory.current.path}${Platform.pathSeparator}.ammds_client');
}
