import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 测试用 Dio 适配器（文档 #79）。
///
/// 让「真实」的 [DioNetworkClient] 逻辑（响应体解包、错误映射、拦截器）
/// 在完全离线的情况下被完整测试。
final class MockHttpAdapter implements HttpClientAdapter {
  /// 创建适配器。
  MockHttpAdapter(this.handler);

  /// 请求处理器：[method, uri, body] → [statusCode, jsonBody]。
  Future<MockHttpResponse> Function(RequestOptions options) handler;

  /// 已处理的请求记录。
  final List<RequestOptions> requests = <RequestOptions>[];

  /// 每个路径的调用次数。
  final Map<String, int> callCounts = <String, int>{};

  /// 请求体（字符串形式）。
  final List<String> requestBodies = <String>[];

  /// 已返回的状态码（按顺序）。
  final List<int> statuses = <int>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final key = '${options.method} ${options.uri.path}';
    callCounts[key] = (callCounts[key] ?? 0) + 1;
    if (options.data != null) {
      requestBodies.add(jsonEncode(options.data));
    }
    final response = await handler(options);
    statuses.add(response.statusCode);
    final payload = jsonEncode(response.body);
    return ResponseBody.fromString(
      payload,
      response.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 模拟响应。
final class MockHttpResponse {
  /// 创建响应。
  const MockHttpResponse(this.statusCode, this.body);

  /// 成功响应（AMMDS 统一响应体）。
  factory MockHttpResponse.success(Object? data) =>
      MockHttpResponse(200, <String, Object?>{'code': 0, 'data': data});

  /// 失败响应。
  factory MockHttpResponse.failure(int statusCode, String message) =>
      MockHttpResponse(statusCode, <String, Object?>{
        'code': statusCode,
        'message': message,
      });

  /// 状态码。
  final int statusCode;

  /// JSON 响应体。
  final Object? body;
}
