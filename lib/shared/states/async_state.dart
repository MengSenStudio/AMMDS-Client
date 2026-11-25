import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/l10n/l10n.dart';
import '../../core/logging/app_logger.dart';

/// 异步状态（文档 #93 / #94）。
sealed class AsyncState<T> {
  /// 创建状态。
  const AsyncState();

  /// 是否处于加载中。
  bool get isLoading => this is Loading<T>;

  /// 是否成功。
  bool get isSuccess => this is Success<T>;

  /// 数据（成功时）。
  T? get dataOrNull => switch (this) {
    Success<T>(:final data) => data,
    _ => null,
  };

  /// 错误（失败时）。
  Object? get errorOrNull => switch (this) {
    Failure<T>(:final error) => error,
    _ => null,
  };
}

/// 初始状态。
final class Initial<T> extends AsyncState<T> {
  /// 创建状态。
  const Initial();
}

/// 加载中。
final class Loading<T> extends AsyncState<T> {
  /// 创建状态。
  const Loading();
}

/// 成功。
final class Success<T> extends AsyncState<T> {
  /// 创建状态。
  const Success(this.data);

  /// 数据。
  final T data;
}

/// 失败。
final class Failure<T> extends AsyncState<T> {
  /// 创建状态。
  const Failure(this.error);

  /// 错误。
  final Object error;
}

/// 把任意错误映射为本地化文案（文档 #32：UI 不解析 HTTP 状态码）。
String localizeError(BuildContext context, Object? error) {
  final l10n = context.l10n;
  return switch (error) {
    null => l10n.unknownError,
    AuthError() => _authMessage(context, error),
    TimeoutError() => l10n.networkTimeout,
    NetworkError() => l10n.networkError,
    ParseError() => l10n.parseError,
    ValidationError() => l10n.validationError,
    ServerError(:final code) when code == 'incompatible_version' =>
      l10n.incompatibleServerVersion,
    // 服务端在统一响应体里给出的业务错误文案（例如「账户或密码错误」「账号已被禁用」）
    // 优先直接展示，避免把明确的登录失败统一吞成「服务端异常」。
    ServerError(:final code, :final message)
        when (code == '401' || code == '403') &&
            message.trim().isNotEmpty &&
            message != 'Server rejected the request' =>
      message,
    ServerError(statusCode: final status) when status == 401 || status == 403 =>
      l10n.authErrorSessionExpired,
    ServerError() => l10n.serverError,
    _ => l10n.unknownError,
  };
}

String _authMessage(BuildContext context, AuthError error) {
  final l10n = context.l10n;
  final message = error.message.toLowerCase();
  if (message.contains('credential') ||
      message.contains('password') ||
      message.contains('unauthorized')) {
    return l10n.authErrorInvalidCredentials;
  }
  return l10n.authErrorSessionExpired;
}

/// 把连接失败原因映射为本地化文案（文档 #58）。
String localizeConnectionFailure(
  BuildContext context,
  ConnectionFailureReason? reason,
) {
  final l10n = context.l10n;
  return switch (reason) {
    ConnectionFailureReason.serverNotFound =>
      l10n.connectionFailedServerNotFound,
    ConnectionFailureReason.networkUnreachable =>
      l10n.connectionFailedNetworkUnreachable,
    ConnectionFailureReason.portUnavailable =>
      l10n.connectionFailedPortUnavailable,
    ConnectionFailureReason.serverRefused => l10n.connectionFailedServerRefused,
    ConnectionFailureReason.unauthorized => l10n.connectionFailedUnauthorized,
    ConnectionFailureReason.incompatibleVersion =>
      l10n.incompatibleServerVersion,
    _ => l10n.connectionFailed,
  };
}

/// 页面控制器基类（文档 #103：页面不直接在 initState 中发请求）。
abstract class PageController<T> extends ChangeNotifier {
  AsyncState<T>? _state;

  /// 当前状态。
  AsyncState<T> get state => _state ?? Initial<T>();

  bool _disposed = false;

  /// 是否已释放。
  bool get isDisposed => _disposed;

  /// 执行加载。
  @protected
  Future<T> load();

  /// 触发加载（幂等安全）。
  Future<void> refresh({bool showLoading = true}) async {
    if (_disposed) {
      return;
    }
    if (showLoading) {
      _setState(Loading<T>());
    }
    try {
      final data = await load();
      _setState(Success<T>(data));
    } on Object catch (error, stackTrace) {
      AppLogger.error('$runtimeType', 'load failed', error, stackTrace);
      _setState(Failure<T>(error));
    }
  }

  /// 更新状态并通知。
  @protected
  void setState(AsyncState<T> next) => _setState(next);

  void _setState(AsyncState<T> next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }
}

/// 让页面控制器与 [ChangeNotifier] 一起使用的监听组件。
class WatchController<T extends ChangeNotifier> extends StatelessWidget {
  /// 创建组件。
  const WatchController({
    super.key,
    required this.controller,
    required this.builder,
  });

  /// 控制器。
  final T controller;

  /// 构建函数。
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) => builder(context),
  );
}

/// 调试辅助：仅 debug 模式输出。
void debugLog(String message) {
  if (kDebugMode) {
    AppLogger.debug('UI', message);
  }
}
