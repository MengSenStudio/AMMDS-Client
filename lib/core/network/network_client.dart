import 'dart:convert';

import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import '../errors/app_exception.dart';

/// 请求用途：不同用途使用不同超时策略（文档 #59）。
enum RequestKind {
  /// 普通业务请求。
  normal,

  /// 搜索请求。
  search,

  /// 图片请求。
  image,

  /// 文件下载。
  download,
}

/// 单次请求的网络选项。
final class NetworkOptions {
  /// 创建选项。
  const NetworkOptions({
    this.kind = RequestKind.normal,
    this.timeout,
    this.retry = false,
    this.maxRetries = 2,
    this.headers = const <String, String>{},
    this.requiresAuth = true,
    this.receiveTimeout,
  });

  /// 用途。
  final RequestKind kind;

  /// 覆盖超时。
  final Duration? timeout;

  /// 是否允许重试。
  final bool retry;

  /// 最大重试次数。
  final int maxRetries;

  /// 附加请求头。
  final Map<String, String> headers;

  /// 是否需要鉴权（登录 / 刷新 / 健康检查为 false）。
  final bool requiresAuth;

  /// 覆盖接收超时。
  final Duration? receiveTimeout;
}

/// 网络客户端抽象（文档 #30 / #71：UI 不直接调用 Dio）。
abstract interface class NetworkClient {
  /// GET。
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    NetworkOptions? options,
    T Function(Object? data)? decode,
  });

  /// POST。
  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, Object?>? query,
    NetworkOptions? options,
    T Function(Object? data)? decode,
  });

  /// PUT。
  Future<T> put<T>(
    String path, {
    Object? body,
    NetworkOptions? options,
    T Function(Object? data)? decode,
  });

  /// DELETE。
  Future<T> delete<T>(
    String path, {
    Object? body,
    NetworkOptions? options,
    T Function(Object? data)? decode,
  });

  /// 下载文件到本地路径，返回文件路径。
  Future<String> download(
    String path,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    NetworkOptions? options,
  });

  /// 释放资源。
  void close();
}

/// 基于 Dio 的默认实现。
final class DioNetworkClient implements NetworkClient {
  /// 创建客户端。
  DioNetworkClient({
    required String baseUrl,
    List<Interceptor> interceptors = const <Interceptor>[],
    HttpClientAdapter? adapter,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: AppTimeouts.connect,
           sendTimeout: AppTimeouts.send,
           receiveTimeout: AppTimeouts.receive,
           responseType: ResponseType.plain,
           headers: const <String, String>{
             'Accept': 'application/json',
             'X-Client': AppConstants.appId,
             'X-Client-Version': AppConstants.appVersion,
           },
           // 由数据层统一处理状态码，便于区分业务错误与网络错误。
           validateStatus: (status) => status != null && status < 600,
         ),
       ) {
    _dio.interceptors.addAll(interceptors);
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
    }
  }

  final Dio _dio;

  /// 底层 Dio 实例（仅装配层可见）。
  Dio get raw => _dio;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    NetworkOptions? options,
    T Function(Object? data)? decode,
  }) => _request<T>(
    method: 'GET',
    path: path,
    query: query,
    options: options,
    decode: decode,
  );

  @override
  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, Object?>? query,
    NetworkOptions? options,
    T Function(Object? data)? decode,
  }) => _request<T>(
    method: 'POST',
    path: path,
    body: body,
    query: query,
    options: options,
    decode: decode,
  );

  @override
  Future<T> put<T>(
    String path, {
    Object? body,
    NetworkOptions? options,
    T Function(Object? data)? decode,
  }) => _request<T>(
    method: 'PUT',
    path: path,
    body: body,
    options: options,
    decode: decode,
  );

  @override
  Future<T> delete<T>(
    String path, {
    Object? body,
    NetworkOptions? options,
    T Function(Object? data)? decode,
  }) => _request<T>(
    method: 'DELETE',
    path: path,
    body: body,
    options: options,
    decode: decode,
  );

  @override
  Future<String> download(
    String path,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    NetworkOptions? options,
  }) async {
    final effective =
        options ?? const NetworkOptions(kind: RequestKind.download);
    try {
      final response = await _dio.download(
        path,
        savePath,
        onReceiveProgress: onReceiveProgress,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout:
              effective.receiveTimeout ??
              effective.timeout ??
              AppTimeouts.downloadReceive,
          headers: effective.headers,
        ),
      );
      if (response.statusCode != null && response.statusCode! >= 400) {
        throw ServerError('Download failed', statusCode: response.statusCode);
      }
      return savePath;
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  @override
  void close() => _dio.close(force: true);

  Future<T> _request<T>({
    required String method,
    required String path,
    Object? body,
    Map<String, Object?>? query,
    NetworkOptions? options,
    T Function(Object? data)? decode,
  }) async {
    final effective = options ?? const NetworkOptions();
    final timeout = effective.timeout ?? _timeoutFor(effective.kind);
    final maxAttempts = effective.retry ? effective.maxRetries + 1 : 1;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _dio.request<Object?>(
          path,
          data: body,
          queryParameters: query,
          options: Options(
            method: method,
            receiveTimeout: effective.receiveTimeout ?? timeout,
            headers: effective.headers,
            extra: <String, Object?>{
              kRequiresAuthKey: effective.requiresAuth,
              kRequestKindKey: effective.kind.name,
            },
          ),
        );
        return _decodeResponse<T>(response, decode);
      } on DioException catch (error) {
        final mapped = mapDioException(error);
        lastError = mapped;
        if (attempt >= maxAttempts || !isRetryable(mapped)) {
          throw mapped;
        }
      } on AppException catch (error) {
        // 业务层已归一化的错误（例如 5xx）同样遵循重试策略（文档 #60）。
        lastError = error;
        if (attempt >= maxAttempts || !isRetryable(error)) {
          rethrow;
        }
      }
    }
    throw lastError is AppException
        ? lastError
        : UnknownError('Request failed', cause: lastError);
  }

  T _decodeResponse<T>(
    Response<Object?> response,
    T Function(Object? data)? decode,
  ) {
    final status = response.statusCode ?? 0;
    final payload = _parseBody(response.data);

    if (status >= 400) {
      throw _mapStatus(status, payload);
    }
    final data = _unwrapEnvelope(payload, status);
    if (decode == null) {
      return data as T;
    }
    try {
      return decode(data);
    } on AppException {
      rethrow;
    } on Object catch (error) {
      throw ParseError('Failed to decode response body', cause: error);
    }
  }

  Object? _parseBody(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is! String) {
      return raw;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(trimmed);
    } on FormatException catch (error) {
      throw ParseError('Response is not valid JSON', cause: error);
    }
  }

  /// AMMDS 统一响应体形如 `{ code, message, data }`；
  /// 若响应体不是该结构，则直接返回原始内容。
  Object? _unwrapEnvelope(Object? payload, int status) {
    if (payload is Map) {
      final hasCode = payload.containsKey('code');
      final hasData = payload.containsKey('data');
      if (hasCode || hasData) {
        final code = payload['code'];
        // 已知 HTTP 状态码时以其为准（例如 5xx 需要保留以支持重试判断）。
        final success = status >= 400
            ? false
            : switch (code) {
                null => true,
                final int numericCode => numericCode == 0 || numericCode == 200,
                final String textCode =>
                  textCode == '0' || textCode == '200' || textCode == 'success',
                _ => true,
              };
        if (!success) {
          throw ServerError(
            _messageOf(payload) ?? 'Server rejected the request',
            statusCode: status >= 400 ? status : null,
            code: code == null ? null : '$code',
          );
        }
        return payload['data'];
      }
    }
    return payload;
  }

  ServerError _mapStatus(int status, Object? payload) {
    final message = payload is Map ? _messageOf(payload) : null;
    return ServerError(
      message ?? 'Request failed with status $status',
      statusCode: status,
      code: payload is Map && payload['code'] != null
          ? '${payload['code']}'
          : null,
    );
  }

  String? _messageOf(Map<Object?, Object?> payload) {
    for (final key in const <String>['message', 'msg', 'error', 'detail']) {
      final value = payload[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  Duration _timeoutFor(RequestKind kind) => switch (kind) {
    RequestKind.normal => AppTimeouts.receive,
    RequestKind.search => AppTimeouts.searchReceive,
    RequestKind.image => AppTimeouts.imageReceive,
    RequestKind.download => AppTimeouts.downloadReceive,
  };
}

/// 标记该请求是否需要携带令牌。
const String kRequiresAuthKey = 'ammds_requires_auth';

/// 标记该请求的用途。
const String kRequestKindKey = 'ammds_request_kind';

/// 判断错误是否适合自动重试（文档 #60）。
///
/// 适合：网络暂时断开、连接超时、5xx。
/// 不适合：400 / 401 / 403 / 404、业务校验失败。
bool isRetryable(AppException error) {
  if (error is TimeoutError || error is NetworkError) {
    return true;
  }
  if (error is ServerError) {
    final status = error.statusCode;
    return status != null && status >= 500;
  }
  return false;
}

/// 把 Dio 异常归一化为 [AppException]（文档 #32）。
AppException mapDioException(DioException error) {
  final status = error.response?.statusCode;
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
      return TimeoutError('Connection timed out', cause: error.error);
    case DioExceptionType.receiveTimeout:
      return TimeoutError('Receive timed out', cause: error.error);
    case DioExceptionType.badCertificate:
      return NetworkError('TLS certificate rejected', cause: error.error);
    case DioExceptionType.connectionError:
      return NetworkError(
        'Network connection failed',
        cause: error.error,
        stackTrace: error.stackTrace,
      );
    case DioExceptionType.cancel:
      return UnknownError('Request cancelled', cause: error.error);
    case DioExceptionType.badResponse:
      if (status == 401 || status == 403) {
        return AuthError(
          'Unauthorized',
          cause: error.error,
          stackTrace: error.stackTrace,
        );
      }
      return ServerError(
        'Request failed with status $status',
        statusCode: status,
        cause: error.error,
      );
    case DioExceptionType.unknown:
    default:
      final cause = error.error;
      if (cause is FormatException) {
        return ParseError('Response is not valid JSON', cause: cause);
      }
      return NetworkError(
        'Unexpected network failure',
        cause: cause,
        stackTrace: error.stackTrace,
      );
  }
}
