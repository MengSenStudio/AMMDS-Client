import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// 日志级别（文档 #48）。
enum LogLevel {
  /// 调试。
  debug,

  /// 常规信息。
  info,

  /// 警告。
  warning,

  /// 错误。
  error,

  /// 致命错误。
  fatal,
}

/// 日志输出后端。
typedef LogSink = void Function(LogRecord record);

/// 单条日志。
final class LogRecord {
  const LogRecord({
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
    required this.timestamp,
  });

  /// 级别。
  final LogLevel level;

  /// 标签（通常是类名或模块名）。
  final String tag;

  /// 日志内容（已脱敏）。
  final String message;

  /// 关联错误。
  final Object? error;

  /// 关联堆栈。
  final StackTrace? stackTrace;

  /// 时间戳。
  final DateTime timestamp;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write(timestamp.toIso8601String())
      ..write(' [${level.name.toUpperCase()}] ')
      ..write('[$tag] ')
      ..write(message);
    if (error != null) {
      buffer.write(' | error=$error');
    }
    return buffer.toString();
  }
}

/// 统一日志能力（文档 #48 / #49）。
///
/// * 生产环境不输出 debug 日志。
/// * 所有输出经过 [sanitize] 脱敏，禁止输出密码、Token、Cookie、Secret。
abstract final class AppLogger {
  static LogLevel minimumLevel = AppConstantsLogDefaults.minimumLevel;
  static final List<LogSink> _sinks = <LogSink>[];

  /// 敏感字段名（小写匹配）。
  static const List<String> sensitiveKeys = <String>[
    'password',
    'passwd',
    'pwd',
    'token',
    'access_token',
    'refresh_token',
    'authorization',
    'cookie',
    'secret',
    'recoverykey',
    'recovery_key',
    'privatekey',
    'private_key',
  ];

  /// 当前最小输出级别。
  static LogLevel get minimumLogLevel => minimumLevel;

  /// 设置最小输出级别。
  static set minimumLogLevel(LogLevel level) {
    minimumLevel = level;
  }

  /// 注册额外输出后端（例如写入文件或上报）。
  static void addSink(LogSink sink) => _sinks.add(sink);

  /// 移除所有额外后端。
  static void clearSinks() => _sinks.clear();

  /// 调试日志。
  static void debug(String tag, String message) =>
      _log(LogLevel.debug, tag, message);

  /// 普通信息。
  static void info(String tag, String message) =>
      _log(LogLevel.info, tag, message);

  /// 警告。
  static void warning(String tag, String message, [Object? error]) =>
      _log(LogLevel.warning, tag, message, error);

  /// 错误。
  static void error(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _log(LogLevel.error, tag, message, error, stackTrace);

  /// 致命错误。
  static void fatal(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _log(LogLevel.fatal, tag, message, error, stackTrace);

  /// 对日志文本脱敏：把 `key=value` / `"key": "value"` 形式中的敏感值替换为 `***`。
  static String sanitize(String input) {
    var output = input;
    for (final key in sensitiveKeys) {
      final pattern = RegExp(
        '(["\']?$key["\']?\\s*[:=]\\s*)("[^"]*"|\'[^\']*\'|[^\\s,;&}]+)',
        caseSensitive: false,
      );
      output = output.replaceAllMapped(
        pattern,
        (match) => '${match.group(1)}***',
      );
    }
    return output;
  }

  static void _log(
    LogLevel level,
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.index < minimumLevel.index) {
      return;
    }
    final record = LogRecord(
      level: level,
      tag: tag,
      message: sanitize(message),
      error: error == null ? null : sanitize('$error'),
      stackTrace: stackTrace,
      timestamp: DateTime.now(),
    );
    if (kDebugMode) {
      developer.log(
        record.toString(),
        name: tag,
        level: _toDeveloperLevel(level),
        error: record.error,
        stackTrace: record.stackTrace,
      );
    }
    for (final sink in _sinks) {
      sink(record);
    }
  }

  static int _toDeveloperLevel(LogLevel level) => switch (level) {
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warning => 900,
    LogLevel.error => 1000,
    LogLevel.fatal => 1200,
  };
}

/// 日志默认值（避免与常量文件相互依赖）。
abstract final class AppConstantsLogDefaults {
  /// 默认最小级别：debug 构建输出 debug，release 构建输出 info。
  static const LogLevel minimumLevel = kReleaseMode
      ? LogLevel.info
      : LogLevel.debug;
}
