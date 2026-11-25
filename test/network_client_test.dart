import 'package:ammds_client/core/errors/app_exception.dart';
import 'package:ammds_client/core/network/network_client.dart';
import 'package:ammds_client/domain/entities/server.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/mock_http_adapter.dart';

void main() {
  group('ServerAddressInput.parse', () {
    test('解析裸 IP', () {
      final parsed = ServerAddressInput.parse('192.168.1.100');
      expect(parsed, isNotNull);
      expect(parsed!.host, '192.168.1.100');
      expect(parsed.protocol, 'http');
      expect(parsed.port, 80);
    });

    test('解析 host:port', () {
      final parsed = ServerAddressInput.parse('192.168.1.100:8080')!;
      expect(parsed.host, '192.168.1.100');
      expect(parsed.port, 8080);
      expect(parsed.url, 'http://192.168.1.100:8080');
    });

    test('解析完整 URL', () {
      final parsed = ServerAddressInput.parse('http://192.168.1.100:8080')!;
      expect(parsed.protocol, 'http');
      expect(parsed.host, '192.168.1.100');
      expect(parsed.port, 8080);
    });

    test('https 默认端口 443', () {
      final parsed = ServerAddressInput.parse('https://ammds.example.com')!;
      expect(parsed.protocol, 'https');
      expect(parsed.port, 443);
      expect(parsed.url, 'https://ammds.example.com');
    });

    test('忽略路径与查询串', () {
      final parsed = ServerAddressInput.parse(
        'http://192.168.1.5:9000/api/foo?x=1',
      )!;
      expect(parsed.host, '192.168.1.5');
      expect(parsed.port, 9000);
    });

    test('支持 IPv6 字面量', () {
      final parsed = ServerAddressInput.parse('http://[fe80::1]:8080')!;
      expect(parsed.host, 'fe80::1');
      expect(parsed.port, 8080);
    });

    test('非法输入返回 null', () {
      for (final input in <String>[
        '',
        '   ',
        'ftp://host',
        'host:abc',
        'host:0',
        'host:70000',
        'http://',
      ]) {
        expect(
          ServerAddressInput.parse(input),
          isNull,
          reason: 'input="$input" 应判定为非法',
        );
      }
    });
  });

  group('ServerProfile', () {
    test('序列化与反序列化往返一致', () {
      final profile = ServerProfile(
        id: 'srv-1',
        name: '客厅服务器',
        host: '192.168.1.10',
        port: 8080,
        protocol: 'http',
        apiVersion: 'v1',
        serverVersion: '1.0.0',
        capabilities: <String, bool>{'media': true},
        lastConnectedAt: DateTime.parse('2026-01-01T10:00:00.000'),
      );
      final restored = ServerProfile.fromJson(profile.toJson());
      expect(restored.id, 'srv-1');
      expect(restored.name, '客厅服务器');
      expect(restored.displayAddress, 'http://192.168.1.10:8080');
      expect(restored.capabilities['media'], isTrue);
      expect(restored.serverVersion, '1.0.0');
      expect(restored.lastConnectedAt, profile.lastConnectedAt);
    });

    test('缺少 id 时由端点派生', () {
      final restored = ServerProfile.fromJson(<String, Object?>{
        'host': '10.0.0.2',
        'port': 81,
        'protocol': 'https',
      });
      expect(restored.id, 'https://10.0.0.2:81');
      expect(restored.isHttps, isTrue);
    });

    test('isSameEndpoint 仅比较端点', () {
      const a = ServerProfile(id: 'a', name: 'A', host: '10.0.0.1', port: 80);
      const b = ServerProfile(id: 'b', name: 'B', host: '10.0.0.1', port: 80);
      const c = ServerProfile(id: 'c', name: 'C', host: '10.0.0.2', port: 80);
      expect(a.isSameEndpoint(b), isTrue);
      expect(a.isSameEndpoint(c), isFalse);
    });
  });

  group('DioNetworkClient', () {
    test('解包 AMMDS 统一响应体', () async {
      final adapter = MockHttpAdapter(
        (options) async =>
            MockHttpResponse.success(<String, Object?>{'value': 42}),
      );
      final client = DioNetworkClient(
        baseUrl: 'http://localhost:1',
        adapter: adapter,
      );
      addTearDown(client.close);

      final result = await client.get<Map<String, Object?>>(
        '/api/client/v1/server/info',
        decode: (data) => (data! as Map).cast<String, Object?>(),
      );
      expect(result['value'], 42);
    });

    test('响应体没有 code 字段时直接返回原始内容', () async {
      final adapter = MockHttpAdapter(
        (options) async =>
            const MockHttpResponse(200, <String, Object?>{'raw': true}),
      );
      final client = DioNetworkClient(
        baseUrl: 'http://localhost:1',
        adapter: adapter,
      );
      addTearDown(client.close);

      final result = await client.get<Map<String, Object?>>(
        '/raw',
        decode: (data) => (data! as Map).cast<String, Object?>(),
      );
      expect(result['raw'], isTrue);
    });

    test('4xx 映射为 ServerError 且保留状态码', () async {
      final adapter = MockHttpAdapter(
        (options) async => MockHttpResponse.failure(404, '找不到资源'),
      );
      final client = DioNetworkClient(
        baseUrl: 'http://localhost:1',
        adapter: adapter,
      );
      addTearDown(client.close);

      await expectLater(
        client.get<void>('/missing', decode: (_) {}),
        throwsA(
          isA<ServerError>()
              .having((error) => error.statusCode, 'statusCode', 404)
              .having((error) => error.message, 'message', '找不到资源'),
        ),
      );
    });

    test('业务失败响应（code!=0）也映射为 ServerError', () async {
      final adapter = MockHttpAdapter(
        (options) async => const MockHttpResponse(200, <String, Object?>{
          'code': 1001,
          'message': '业务校验失败',
        }),
      );
      final client = DioNetworkClient(
        baseUrl: 'http://localhost:1',
        adapter: adapter,
      );
      addTearDown(client.close);

      await expectLater(
        client.get<void>('/biz', decode: (_) {}),
        throwsA(
          isA<ServerError>()
              .having((error) => error.code, 'code', '1001')
              .having((error) => error.message, 'message', '业务校验失败'),
        ),
      );
    });

    test('非 JSON 响应映射为 ParseError', () async {
      final adapter = MockHttpAdapter(
        (options) async => const MockHttpResponse(200, 'plain text'),
      );
      final client = DioNetworkClient(
        baseUrl: 'http://localhost:1',
        adapter: adapter,
      );
      addTearDown(client.close);

      await expectLater(
        client.get<void>('/text', decode: (_) {}),
        throwsA(isA<ParseError>()),
      );
    });

    test('查询参数与请求体被正确传递', () async {
      final adapter = MockHttpAdapter(
        (options) async => MockHttpResponse.success(null),
      );
      final client = DioNetworkClient(
        baseUrl: 'http://localhost:1',
        adapter: adapter,
      );
      addTearDown(client.close);

      await client.get<void>(
        '/api/client/v1/media',
        query: <String, Object?>{'cursor': '2', 'keyword': 'bob'},
        decode: (_) {},
      );
      expect(adapter.requests.single.uri.queryParameters['cursor'], '2');
      expect(adapter.requests.single.uri.queryParameters['keyword'], 'bob');

      await client.post<void>(
        '/api/client/v1/auth/login',
        body: <String, Object?>{'username': 'admin'},
        decode: (_) {},
      );
      expect(adapter.requestBodies.last, contains('admin'));
    });

    test('可重试错误会按配置重试', () async {
      var attempts = 0;
      final adapter = MockHttpAdapter((options) async {
        attempts++;
        if (attempts < 3) {
          return const MockHttpResponse(503, <String, Object?>{
            'code': 503,
            'message': '服务不可用',
          });
        }
        return MockHttpResponse.success('ok');
      });
      final client = DioNetworkClient(
        baseUrl: 'http://localhost:1',
        adapter: adapter,
      );
      addTearDown(client.close);

      final result = await client.get<String>(
        '/flaky',
        options: const NetworkOptions(retry: true, maxRetries: 3),
        decode: (data) => '$data',
      );
      expect(
        result,
        'ok',
        reason: 'attempts=$attempts statuses=${adapter.statuses}',
      );
      expect(attempts, 3);
    });

    test('400 不重试', () async {
      var attempts = 0;
      final adapter = MockHttpAdapter((options) async {
        attempts++;
        return MockHttpResponse.failure(400, '参数错误');
      });
      final client = DioNetworkClient(
        baseUrl: 'http://localhost:1',
        adapter: adapter,
      );
      addTearDown(client.close);

      await expectLater(
        client.get<void>(
          '/bad',
          options: const NetworkOptions(retry: true, maxRetries: 3),
          decode: (_) {},
        ),
        throwsA(isA<ServerError>()),
      );
      expect(attempts, 1);
    });
  });

  group('isRetryable', () {
    test('网络错误与 5xx 可重试，4xx 不可重试', () {
      expect(isRetryable(const NetworkError('x')), isTrue);
      expect(isRetryable(const TimeoutError('x')), isTrue);
      expect(isRetryable(const ServerError('x', statusCode: 500)), isTrue);
      expect(isRetryable(const ServerError('x', statusCode: 503)), isTrue);
      expect(isRetryable(const ServerError('x', statusCode: 400)), isFalse);
      expect(isRetryable(const ServerError('x', statusCode: 401)), isFalse);
      expect(isRetryable(const ServerError('x', statusCode: 404)), isFalse);
      expect(isRetryable(const AuthError('x')), isFalse);
      expect(isRetryable(const ValidationError('x')), isFalse);
    });
  });
}
