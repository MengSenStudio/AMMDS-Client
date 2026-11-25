import 'package:dio/dio.dart';

import '../../errors/app_exception.dart';
import '../../logging/app_logger.dart';
import '../network_client.dart';

/// 鉴权拦截器（文档 #23 / #26 / #28 / #29）。
///
/// 职责：
/// 1. 为需要鉴权的请求注入 `Authorization: Bearer <accessToken>`。
/// 2. 访问令牌接近过期时，在发出业务请求**之前**主动刷新
///    （请求驱动 + 生命周期驱动，而不是固定定时器）。
/// 3. 收到 401 时刷新令牌并重放一次请求。
/// 4. 刷新失败时清理认证信息并通知上层跳转登录页。
///
/// 并发刷新由注入的 [refreshToken] 保证「同一时间只有一个刷新请求」：
/// 该回调由 SessionManager 提供，内部使用共享 Future 实现。
final class AuthInterceptor extends Interceptor {
  /// 创建拦截器。
  AuthInterceptor({
    required this.readAccessToken,
    required this.refreshToken,
    required this.onAuthenticationLost,
    this.requiresAuthResolver,
  });

  /// 读取当前访问令牌。
  final Future<String?> Function() readAccessToken;

  /// 刷新令牌；返回新的访问令牌，失败返回 `null`。
  ///
  /// 实现方必须保证并发调用只会产生一次真实的刷新请求。
  final Future<String?> Function() refreshToken;

  /// 认证彻底失效时的回调（清理状态并跳转登录）。
  final void Function(Object error) onAuthenticationLost;

  /// 判断某个请求是否需要鉴权，默认读取请求 extra 标记。
  final bool Function(RequestOptions options)? requiresAuthResolver;

  static const String _retriedFlag = 'ammds_auth_retried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_requiresAuth(options)) {
      handler.next(options);
      return;
    }

    // 令牌读取本身就是「请求驱动刷新」的唯一入口：
    // SessionManager.currentAccessToken() 会在剩余有效期进入刷新窗口时
    // 触发一次刷新（并发单飞）。这里**不能**再额外无条件刷新一次，
    // 否则每个业务请求都会重新签发令牌——服务端每次签发都会记录一条
    // 「登录成功」，主界面并发加载四个列表就会瞬间刷出多条登录日志。
    final token = await readAccessToken();
    if (token == null || token.isEmpty) {
      handler.next(options);
      return;
    }

    options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final status = response?.statusCode;
    final alreadyRetried = err.requestOptions.extra[_retriedFlag] == true;

    if (status != 401 || alreadyRetried || !_requiresAuth(err.requestOptions)) {
      handler.next(err);
      return;
    }

    AppLogger.info(
      'AuthInterceptor',
      'received 401 for ${err.requestOptions.path}, refreshing token',
    );
    final refreshed = await refreshToken();
    if (refreshed == null || refreshed.isEmpty) {
      onAuthenticationLost(
        err.error is AppException
            ? err.error!
            : AuthError('Session expired', cause: err.error),
      );
      handler.next(err);
      return;
    }

    final options = err.requestOptions
      ..extra[_retriedFlag] = true
      ..headers['Authorization'] = 'Bearer $refreshed';
    try {
      final retried = await _dioRetry(options);
      handler.resolve(retried);
    } on DioException catch (retryError) {
      if (retryError.response?.statusCode == 401) {
        onAuthenticationLost(
          AuthError('Session expired after refresh', cause: retryError.error),
        );
      }
      handler.next(retryError);
    }
  }

  /// 由拦截器持有的 Dio 实例用于重放请求。
  ///
  /// 通过 [attach] 注入，避免拦截器与 HttpClient 相互构造依赖。
  Dio? _dio;

  /// 绑定所属 Dio 实例。
  void attach(Dio dio) => _dio = dio;

  Future<Response<Object?>> _dioRetry(RequestOptions options) {
    final dio = _dio;
    if (dio == null) {
      throw StateError('AuthInterceptor is not attached to a Dio instance');
    }
    return dio.fetch<Object?>(options);
  }

  bool _requiresAuth(RequestOptions options) {
    final resolver = requiresAuthResolver;
    if (resolver != null) {
      return resolver(options);
    }
    final flag = options.extra[kRequiresAuthKey];
    return flag is! bool || flag;
  }
}
