import 'dart:convert';

import 'package:ammds_client/core/constants/discovery_constants.dart';
import 'package:ammds_client/core/discovery/discovery_codec.dart';
import 'package:ammds_client/core/discovery/discovery_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiscoveryCodec', () {
    test('编码请求包含协议、版本、服务类型与客户端信息', () {
      final bytes = DiscoveryCodec.encodeRequest(const DiscoveryRequest());
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;

      expect(decoded['protocol'], DiscoveryConstants.protocol);
      expect(decoded['version'], DiscoveryConstants.version);
      expect(decoded['service'], DiscoveryConstants.service);
      expect(decoded['type'], 'discover');
      expect(decoded['client_id'], isNotEmpty);
      expect(decoded['client_version'], isNotEmpty);
    });

    test('解析标准响应', () {
      final payload = DiscoveryCodec.encodeResponse(
        const DiscoveryResponse(
          protocol: DiscoveryConstants.protocol,
          version: 1,
          service: DiscoveryConstants.service,
          serverId: 'server-a',
          name: 'AMMDS Server A',
          host: '192.168.1.100',
          port: 8080,
          apiVersion: 'v1',
          versionName: '1.0.0',
          capabilities: <String, bool>{'media': true, 'novel': false},
        ),
      );

      final response = DiscoveryCodec.decodeResponse(
        payload,
        sourceAddress: '192.168.1.100',
      );

      expect(response.name, 'AMMDS Server A');
      expect(response.host, '192.168.1.100');
      expect(response.port, 8080);
      expect(response.serverId, 'server-a');
      expect(response.apiVersion, 'v1');
      expect(response.versionName, '1.0.0');
      expect(response.protocolName, 'http');
      expect(response.capabilities['media'], isTrue);
      expect(response.capabilities['novel'], isFalse);
      expect(response.displayAddress, 'http://192.168.1.100:8080');
    });

    test('响应缺少 host 时回退到报文来源地址', () {
      final payload = utf8.encode(
        jsonEncode(<String, Object?>{
          'protocol': 'ammds-discovery',
          'version': 1,
          'service': 'ammds',
          'name': 'No Host',
          'port': 9000,
        }),
      );

      final response = DiscoveryCodec.decodeResponse(
        payload,
        sourceAddress: '10.0.0.7',
      );

      expect(response.host, '10.0.0.7');
      expect(response.sourceIsFallback, isTrue);
      expect(response.serverId, '10.0.0.7:9000');
    });

    test('响应缺少 server_id 时由地址派生', () {
      final payload = utf8.encode(
        jsonEncode(<String, Object?>{
          'protocol': 'ammds-discovery',
          'version': 1,
          'service': 'ammds',
          'host': '192.168.0.5',
          'port': 80,
        }),
      );

      final response = DiscoveryCodec.decodeResponse(
        payload,
        sourceAddress: '192.168.0.5',
      );

      expect(response.serverId, '192.168.0.5:80');
      expect(response.name, 'AMMDS Server');
    });

    test('https 响应使用 https 协议名', () {
      final payload = DiscoveryCodec.encodeResponse(
        const DiscoveryResponse(
          protocol: DiscoveryConstants.protocol,
          version: 1,
          service: DiscoveryConstants.service,
          serverId: 'secure',
          name: 'Secure',
          host: 'ammds.local',
          port: 443,
          https: true,
        ),
      );

      final response = DiscoveryCodec.decodeResponse(
        payload,
        sourceAddress: '10.0.0.1',
      );

      expect(response.protocolName, 'https');
      expect(response.displayAddress, 'https://ammds.local:443');
    });

    test('非 JSON 报文抛出 malformed', () {
      expect(
        () => DiscoveryCodec.decodeResponse(
          utf8.encode('not json at all'),
          sourceAddress: '127.0.0.1',
        ),
        throwsA(
          isA<DiscoveryProtocolException>().having(
            (error) => error.code,
            'code',
            DiscoveryErrorCodes.malformed,
          ),
        ),
      );
    });

    test('JSON 根不是对象时抛出 malformed', () {
      expect(
        () => DiscoveryCodec.decodeResponse(
          utf8.encode('[1,2,3]'),
          sourceAddress: '127.0.0.1',
        ),
        throwsA(
          isA<DiscoveryProtocolException>().having(
            (error) => error.code,
            'code',
            DiscoveryErrorCodes.malformed,
          ),
        ),
      );
    });

    test('协议标识不匹配抛出 protocolMismatch', () {
      final payload = utf8.encode(
        jsonEncode(<String, Object?>{
          'protocol': 'other-protocol',
          'version': 1,
          'service': 'ammds',
          'port': 8080,
        }),
      );

      expect(
        () =>
            DiscoveryCodec.decodeResponse(payload, sourceAddress: '127.0.0.1'),
        throwsA(
          isA<DiscoveryProtocolException>().having(
            (error) => error.code,
            'code',
            DiscoveryErrorCodes.protocolMismatch,
          ),
        ),
      );
    });

    test('服务类型不匹配抛出 serviceMismatch', () {
      final payload = utf8.encode(
        jsonEncode(<String, Object?>{
          'protocol': 'ammds-discovery',
          'version': 1,
          'service': 'other-service',
          'port': 8080,
        }),
      );

      expect(
        () =>
            DiscoveryCodec.decodeResponse(payload, sourceAddress: '127.0.0.1'),
        throwsA(
          isA<DiscoveryProtocolException>().having(
            (error) => error.code,
            'code',
            DiscoveryErrorCodes.serviceMismatch,
          ),
        ),
      );
    });

    test('协议版本过高抛出 versionIncompatible', () {
      final payload = utf8.encode(
        jsonEncode(<String, Object?>{
          'protocol': 'ammds-discovery',
          'version': 99,
          'service': 'ammds',
          'port': 8080,
        }),
      );

      expect(
        () =>
            DiscoveryCodec.decodeResponse(payload, sourceAddress: '127.0.0.1'),
        throwsA(
          isA<DiscoveryProtocolException>().having(
            (error) => error.code,
            'code',
            DiscoveryErrorCodes.versionIncompatible,
          ),
        ),
      );
    });

    test('端口非法抛出 malformed', () {
      for (final port in <Object?>[null, 0, -1, 70000, 'abc']) {
        final payload = utf8.encode(
          jsonEncode(<String, Object?>{
            'protocol': 'ammds-discovery',
            'version': 1,
            'service': 'ammds',
            'port': port,
          }),
        );
        expect(
          () => DiscoveryCodec.decodeResponse(
            payload,
            sourceAddress: '127.0.0.1',
          ),
          throwsA(isA<DiscoveryProtocolException>()),
          reason: 'port=$port 应被拒绝',
        );
      }
    });

    test('超长报文抛出 tooLarge', () {
      final oversized = List<int>.filled(
        DiscoveryConstants.maxDatagramSize + 1,
        0x41,
      );
      expect(
        () => DiscoveryCodec.decodeResponse(
          oversized,
          sourceAddress: '127.0.0.1',
        ),
        throwsA(
          isA<DiscoveryProtocolException>().having(
            (error) => error.code,
            'code',
            DiscoveryErrorCodes.tooLarge,
          ),
        ),
      );
    });

    test('非布尔能力值被忽略', () {
      final payload = utf8.encode(
        jsonEncode(<String, Object?>{
          'protocol': 'ammds-discovery',
          'version': 1,
          'service': 'ammds',
          'port': 8080,
          'capabilities': <String, Object?>{
            'media': true,
            'novel': 'yes',
            'comic': 1,
          },
        }),
      );

      final response = DiscoveryCodec.decodeResponse(
        payload,
        sourceAddress: '127.0.0.1',
      );

      expect(response.capabilities.keys, <String>['media']);
    });

    test('忽略比当前更高的协议版本以外的小版本差异', () {
      final payload = utf8.encode(
        jsonEncode(<String, Object?>{
          'protocol': 'ammds-discovery',
          'version': 1,
          'service': 'ammds',
          'port': 8080,
        }),
      );
      final response = DiscoveryCodec.decodeResponse(
        payload,
        sourceAddress: '127.0.0.1',
      );
      expect(response.version, 1);
    });
  });

  group('DiscoveryResponse', () {
    test('相同 serverId 视为同一个服务端', () {
      const a = DiscoveryResponse(
        protocol: 'ammds-discovery',
        version: 1,
        service: 'ammds',
        serverId: 'same',
        name: 'A',
        host: '10.0.0.1',
        port: 80,
      );
      const b = DiscoveryResponse(
        protocol: 'ammds-discovery',
        version: 1,
        service: 'ammds',
        serverId: 'same',
        name: 'B',
        host: '10.0.0.2',
        port: 81,
      );
      expect(a, equals(b));
      expect(a.dedupeKey, 'same');
    });
  });
}
