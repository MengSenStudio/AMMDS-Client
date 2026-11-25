import 'package:ammds_client/core/constants/discovery_constants.dart';
import 'package:ammds_client/core/discovery/discovery_models.dart';
import 'package:ammds_client/core/discovery/discovery_service.dart';
import 'package:ammds_client/core/discovery/discovery_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/mock_ammds_server.dart';

void main() {
  DiscoveryResponse response({
    required String id,
    String host = '192.168.1.10',
    int port = 8080,
    String name = 'AMMDS Server',
  }) => DiscoveryResponse(
    protocol: DiscoveryConstants.protocol,
    version: DiscoveryConstants.version,
    service: DiscoveryConstants.service,
    serverId: id,
    name: name,
    host: host,
    port: port,
    versionName: '1.0.0',
  );

  group('DiscoveryService（内存传输）', () {
    test('已知服务端地址会作为单播探测目标下发', () async {
      // 广播在部分网络里被丢弃，单播仍然通；已保存的地址要能点名探测。
      final transport = FakeDiscoveryTransport();
      final service = DiscoveryService(
        transport: transport,
        tuning: DiscoveryTuning(
          probeInterval: const Duration(milliseconds: 5),
          probeTimeout: const Duration(milliseconds: 10),
          probeRounds: 1,
        ),
      );

      service.useKnownHosts(<String>['192.168.1.50', '10.0.0.7']);
      await service.discover();

      expect(transport.knownHosts, containsAll(<String>['192.168.1.50', '10.0.0.7']));
      expect(transport.probeTargets, contains('192.168.1.50'));
    });

    test('发现单个服务端', () async {
      final transport = FakeDiscoveryTransport(
        replies: <DiscoveryResponse>[response(id: 's1')],
      );
      final service = DiscoveryService(
        transport: transport,
        tuning: DiscoveryTuning(
          probeInterval: const Duration(milliseconds: 10),
          probeTimeout: const Duration(milliseconds: 20),
          probeRounds: 2,
        ),
      );

      final outcome = await service.discover();

      expect(outcome.servers, hasLength(1));
      expect(outcome.servers.single.serverId, 's1');
      expect(outcome.servers.single.displayAddress, 'http://192.168.1.10:8080');
      expect(outcome.invalidResponses, 0);
      expect(transport.sendCount, 2);
      expect(transport.closed, isTrue);
    });

    test('发现多个服务端', () async {
      final transport = FakeDiscoveryTransport(
        replies: <DiscoveryResponse>[
          response(id: 's1', host: '192.168.1.10'),
          response(id: 's2', host: '192.168.1.11', port: 9090),
          response(id: 's3', host: '192.168.1.12', port: 7070),
        ],
      );
      final service = DiscoveryService(
        transport: transport,
        tuning: DiscoveryTuning(
          probeInterval: const Duration(milliseconds: 10),
          probeTimeout: const Duration(milliseconds: 20),
          probeRounds: 1,
        ),
      );

      final outcome = await service.discover();

      expect(outcome.servers, hasLength(3));
      expect(
        outcome.servers.map((server) => server.serverId),
        containsAll(<String>['s1', 's2', 's3']),
      );
    });

    test('重复响应只保留一次', () async {
      final transport = FakeDiscoveryTransport(
        replies: <DiscoveryResponse>[
          response(id: 'dup', host: '192.168.1.10'),
          response(id: 'dup', host: '192.168.1.10'),
          response(id: 'dup', host: '192.168.1.10'),
        ],
      );
      final service = DiscoveryService(
        transport: transport,
        tuning: DiscoveryTuning(
          probeInterval: const Duration(milliseconds: 5),
          probeTimeout: const Duration(milliseconds: 10),
          probeRounds: 3,
        ),
      );

      final outcome = await service.discover();

      expect(outcome.servers, hasLength(1));
    });

    test('无服务端时返回空结果而不抛异常', () async {
      final service = DiscoveryService(
        transport: FakeDiscoveryTransport(),
        tuning: DiscoveryTuning(
          probeInterval: const Duration(milliseconds: 5),
          probeTimeout: const Duration(milliseconds: 10),
          probeRounds: 2,
        ),
      );

      final outcome = await service.discover();

      expect(outcome.servers, isEmpty);
      expect(outcome.isEmpty, isTrue);
    });

    test('非法响应被忽略且计入 invalidResponses', () async {
      final transport = FakeDiscoveryTransport(
        replies: <DiscoveryResponse>[response(id: 'valid')],
        rawReplies: <List<int>>[
          <int>[0x7b, 0x7d], // "{}"，缺少协议字段
          <int>[0x6e, 0x6f, 0x74, 0x20, 0x6a, 0x73, 0x6f, 0x6e], // "not json"
        ],
      );
      final service = DiscoveryService(
        transport: transport,
        tuning: DiscoveryTuning(
          probeInterval: const Duration(milliseconds: 5),
          probeTimeout: const Duration(milliseconds: 10),
          probeRounds: 1,
        ),
      );

      final outcome = await service.discover();

      expect(outcome.servers, hasLength(1));
      expect(outcome.invalidResponses, 2);
    });

    test('发送失败时记录错误但流程正常结束', () async {
      final service = DiscoveryService(
        transport: FakeDiscoveryTransport(throwOnSend: true),
        tuning: DiscoveryTuning(
          probeInterval: const Duration(milliseconds: 5),
          probeTimeout: const Duration(milliseconds: 10),
          probeRounds: 2,
        ),
      );

      final outcome = await service.discover();

      expect(outcome.servers, isEmpty);
      expect(outcome.error, isNotNull);
      expect(outcome.rounds, 2);
    });

    test('超时结束并标记 timedOut', () async {
      final service = DiscoveryService(
        transport: FakeDiscoveryTransport(),
        tuning: DiscoveryTuning(
          probeInterval: const Duration(milliseconds: 5),
          probeTimeout: const Duration(milliseconds: 10),
          probeRounds: 1,
        ),
      );

      final outcome = await service.discover();

      expect(outcome.timedOut, isTrue);
    });

    test('发现过程中通过回调增量上报', () async {
      final transport = FakeDiscoveryTransport(
        replies: <DiscoveryResponse>[
          response(id: 'a'),
          response(id: 'b', host: '192.168.1.20'),
        ],
      );
      final service = DiscoveryService(
        transport: transport,
        tuning: DiscoveryTuning(
          probeInterval: const Duration(milliseconds: 5),
          probeTimeout: const Duration(milliseconds: 10),
          probeRounds: 1,
        ),
      );

      final seen = <String>[];
      await service.discover(
        onServerFound: (server) => seen.add(server.serverId),
      );

      expect(seen, containsAll(<String>['a', 'b']));
    });

    test('重复调用 discover 会被拒绝', () async {
      final service = DiscoveryService(
        transport: FakeDiscoveryTransport(),
        tuning: DiscoveryTuning(
          probeInterval: const Duration(milliseconds: 40),
          probeTimeout: const Duration(milliseconds: 40),
          probeRounds: 2,
        ),
      );
      final first = service.discover();
      expect(service.isRunning, isTrue);
      await expectLater(service.discover(), throwsStateError);
      await first;
      expect(service.isRunning, isFalse);
    });
  });

  group('发现 UDP 链路（真实 socket）', () {
    late MockAmmdsServer server;

    setUp(() async {
      server = MockAmmdsServer();
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('UDP 单播探测能收到符合协议的响应', () async {
      final received = await server.probeDiscovery();
      expect(received, isTrue, reason: '服务端应响应发现探测');
      expect(server.discoveryProbes, greaterThan(0));
    });

    test('通过 UdpDiscoveryTransport 真实收发（单播目标注入）', () async {
      final transport = UdpDiscoveryTransport(
        additionalProbeTargets: <String>['127.0.0.1'],
        enableBroadcast: false,
      );
      final service = DiscoveryService(
        transport: transport,
        tuning: DiscoveryTuning(
          probeInterval: const Duration(milliseconds: 30),
          probeTimeout: const Duration(milliseconds: 60),
          probeRounds: 3,
        ),
      );

      final outcome = await service.discover();

      expect(
        outcome.servers.map((server) => server.serverId),
        contains('test-server-0001'),
      );
      final discovered = outcome.servers.firstWhere(
        (item) => item.serverId == 'test-server-0001',
      );
      expect(discovered.port, server.port);
      expect(discovered.apiVersion, 'v1');
      expect(discovered.host, isNotEmpty);
    });
  });
}
