import 'socket_failure.dart';

/// 客户端统一错误模型（文档 #32）。
///
/// UI 层禁止直接解析 HTTP 状态码，所有错误在数据层/领域层归一化为
/// [AppException] 的子类型，UI 只需根据类型选择文案。
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause, this.stackTrace});

  /// 面向开发者的错误描述（不直接展示给用户）。
  final String message;

  /// 底层原因。
  final Object? cause;

  /// 原始堆栈。
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// 网络层错误：连接失败、DNS 失败、网络不可达等。
final class NetworkError extends AppException {
  const NetworkError(super.message, {super.cause, super.stackTrace});
}

/// 认证/授权错误。
final class AuthError extends AppException {
  const AuthError(super.message, {super.cause, super.stackTrace});
}

/// 服务端错误（5xx、业务失败响应）。
final class ServerError extends AppException {
  const ServerError(
    super.message, {
    this.statusCode,
    this.code,
    super.cause,
    super.stackTrace,
  });

  /// HTTP 状态码（如有）。
  final int? statusCode;

  /// 服务端业务错误码（如有）。
  final String? code;
}

/// 输入校验错误。
final class ValidationError extends AppException {
  const ValidationError(super.message, {this.field, super.cause});

  /// 出错的字段名（如有）。
  final String? field;
}

/// 请求超时。
final class TimeoutError extends AppException {
  const TimeoutError(super.message, {super.cause, super.stackTrace});
}

/// 数据解析错误。
final class ParseError extends AppException {
  const ParseError(super.message, {super.cause, super.stackTrace});
}

/// 未归类的错误。
final class UnknownError extends AppException {
  const UnknownError(super.message, {super.cause, super.stackTrace});
}

/// 连接失败原因（文档 #58：不能统一显示「连接失败」）。
enum ConnectionFailureReason {
  /// 服务端不存在（DNS / 主机解析失败）。
  serverNotFound,

  /// 网络不可达。
  networkUnreachable,

  /// 端口不可用（服务端未启动）。
  portUnavailable,

  /// 服务端拒绝连接。
  serverRefused,

  /// 认证失败。
  unauthorized,

  /// 服务端版本不兼容。
  incompatibleVersion,

  /// 其他未知原因。
  unknown,
}

/// 连接测试结果。
final class ConnectionCheckResult {
  const ConnectionCheckResult._({
    required this.success,
    this.reason,
    this.message,
    this.serverVersion,
    this.apiVersion,
    this.capabilities = const <String, bool>{},
  });

  /// 成功。
  const ConnectionCheckResult.success({
    String? serverVersion,
    String? apiVersion,
    Map<String, bool> capabilities = const <String, bool>{},
  }) : this._(
         success: true,
         serverVersion: serverVersion,
         apiVersion: apiVersion,
         capabilities: capabilities,
       );

  /// 失败。
  const ConnectionCheckResult.failure(
    ConnectionFailureReason reason, {
    String? message,
  }) : this._(success: false, reason: reason, message: message);

  /// 是否成功。
  final bool success;

  /// 失败原因。
  final ConnectionFailureReason? reason;

  /// 附加描述。
  final String? message;

  /// 服务端版本。
  final String? serverVersion;

  /// API 版本。
  final String? apiVersion;

  /// 服务端能力。
  final Map<String, bool> capabilities;
}

/// 把任意错误归类为 [ConnectionFailureReason]（文档 #58）。
ConnectionFailureReason classifyConnectionFailure(Object error) {
  if (error is ConnectionCheckResult) {
    return error.reason ?? ConnectionFailureReason.unknown;
  }
  if (error is AuthError) {
    return ConnectionFailureReason.unauthorized;
  }
  if (error is TimeoutError) {
    return ConnectionFailureReason.serverNotFound;
  }
  if (error is NetworkError) {
    final cause = error.cause;
    // 套接字 OS 错误码（Windows / Linux / macOS 取值不同）优先，其次看错误文案。
    final reason = _classifySocketCode(socketErrorCode(cause));
    if (reason != null) {
      return reason;
    }
    final text = socketErrorMessage(cause) ?? error.message.toLowerCase();
    if (text.contains('refused')) {
      return ConnectionFailureReason.serverRefused;
    }
    if (text.contains('unreachable')) {
      return ConnectionFailureReason.networkUnreachable;
    }
    if (text.contains('failed host lookup') || text.contains('not found')) {
      return ConnectionFailureReason.serverNotFound;
    }
    if (text.contains('no route')) {
      return ConnectionFailureReason.networkUnreachable;
    }
    if (text.contains('host not found') ||
        text.contains('nodename nor servname') ||
        text.contains('no address associated')) {
      return ConnectionFailureReason.serverNotFound;
    }
    return ConnectionFailureReason.networkUnreachable;
  }
  if (error is ServerError) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return ConnectionFailureReason.unauthorized;
    }
    return ConnectionFailureReason.serverRefused;
  }
  return ConnectionFailureReason.unknown;
}

/// 依据套接字 OS 错误码归类，无法判定时返回 `null`。
ConnectionFailureReason? _classifySocketCode(int? code) {
  // Windows: 10061 连接被拒绝；Linux/macOS: 111 连接被拒绝。
  if (code == 10061 || code == 111) {
    return ConnectionFailureReason.serverRefused;
  }
  // Windows: 10060/10065 超时、不可达；Linux: 113 无路由。
  if (code == 10060 || code == 10065 || code == 113) {
    return ConnectionFailureReason.networkUnreachable;
  }
  return null;
}
