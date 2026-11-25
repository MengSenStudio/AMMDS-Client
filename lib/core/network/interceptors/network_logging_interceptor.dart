import 'package:dio/dio.dart';

import '../../constants/app_constants.dart';
import '../../logging/app_logger.dart';

/// 网络日志拦截器（文档 #49）。
///
/// 开发环境记录 URL / Method / Status / Duration / Request ID，
/// 并对敏感 Header 与 Body 脱敏。
final class NetworkLoggingInterceptor extends Interceptor {
  /// 创建拦截器。
  NetworkLoggingInterceptor({this.enabled = true});

  /// 是否启用。
  final bool enabled;

  static const String _tag = 'HTTP';
  static const String _startKey = 'ammds_request_start';
  static const String _idKey = 'ammds_request_id';

  static int _sequence = 0;

  /// 敏感请求头。
  static const List<String> _sensitiveHeaders = <String>[
    'authorization',
    'cookie',
    'set-cookie',
    'proxy-authorization',
  ];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!enabled) {
      handler.next(options);
      return;
    }
    final id = '#${++_sequence}';
    options.extra[_startKey] = DateTime.now().microsecondsSinceEpoch;
    options.extra[_idKey] = id;
    final headers = _sanitizeHeaders(options.headers);
    final body = options.data == null
        ? ''
        : ' body=${AppLogger.sanitize('${options.data}')}';
    AppLogger.debug(
      _tag,
      '→ $id ${options.method} ${options.uri} headers=$headers$body',
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    if (!enabled) {
      handler.next(response);
      return;
    }
    AppLogger.debug(
      _tag,
      '← ${response.requestOptions.extra[_idKey] ?? '#'} '
      '${response.statusCode} ${response.requestOptions.uri} '
      '${_durationOf(response.requestOptions)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!enabled) {
      handler.next(err);
      return;
    }
    AppLogger.warning(
      _tag,
      '✗ ${err.requestOptions.extra[_idKey] ?? '#'} ${err.type.name} '
      '${err.requestOptions.uri} ${_durationOf(err.requestOptions)} '
      '${AppLogger.sanitize(err.message ?? '')}',
      err.error,
    );
    handler.next(err);
  }

  String _durationOf(RequestOptions options) {
    final start = options.extra[_startKey];
    if (start is! int) {
      return '';
    }
    final elapsed = DateTime.now().microsecondsSinceEpoch - start;
    return '${(elapsed / 1000).toStringAsFixed(1)}ms';
  }

  Map<String, String> _sanitizeHeaders(Map<String, dynamic> headers) {
    final result = <String, String>{};
    headers.forEach((key, value) {
      if (_sensitiveHeaders.contains(key.toLowerCase())) {
        result[key] = '***';
      } else {
        result[key] = AppLogger.sanitize('$value');
      }
    });
    result['X-Client'] = AppConstants.appId;
    return result;
  }
}
