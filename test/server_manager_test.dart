import 'dart:io';

import 'package:ammds_client/core/constants/discovery_constants.dart';
import 'package:ammds_client/core/discovery/discovery_models.dart';
import 'package:ammds_client/core/discovery/discovery_service.dart';
import 'package:ammds_client/core/discovery/discovery_transport.dart';
import 'package:ammds_client/core/errors/app_exception.dart';
import 'package:ammds_client/core/storage/storage_impl.dart';
import 'package:ammds_client/data/repositories/settings_repository_impl.dart';
import 'package:ammds_client/domain/entities/server.dart';
import 'package:ammds_client/domain/entities/splash.dart';
import 'package:ammds_client/domain/repositories/repositories.dart';
import 'package:ammds_client/domain/services/server_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可脚本化的服务端仓库。
final class FakeServerRepository implements ServerRepository {
  int discoverCalls = 0;
  int probeCalls = 0;
  int fetchInfoCalls = 0;

  Object? probeError;
  ServerProfile? probeResult;
  ServerProfile? infoResult;

  @override
  Future<List<ServerProfile>> discover({
    void Function(ServerProfile server)? onServerFound,
  }) async {
    discoverCalls++;
    return const <ServerProfile>[];
  }

  @override
  Future<ServerProfile> probe(ServerProfile candidate) async {
    probeCalls++;
    final error = probeError;
    if (error != null) {
      throw error;
    }
    final result =
        probeResult ?? candidate.copyWith(lastConnectedAt: DateTime.now());
    // 真实实现会在探测成功后读取服务端信息，此处保持一致。
    return fetchServerInfo(result);
  }

  @override
  Future<ServerProfile> fetchServerInfo(ServerProfile server) async {
    fetchInfoCalls++;
    return infoResult ??
        server.copyWith(
          serverVersion: '1.0.0',
          apiVersion: 'v1',
          capabilities: const <String, bool>{'media': true},
        );
  }

  @override
  Future<SplashConfig> fetchSplashConfig(
    ServerProfile server, {
    required String fallbackProductName,
    required String fallbackCopyright,
  }) async => SplashConfig.local(
    productName: fallbackProductName,
    copyright: fallbackCopyright,
  );
}

const ServerProfile _discovered = ServerProfile(
  id: 'test-server-0001',
  name: 'AMMDS Test Server',
  host: '192.168.1.50',
  port: 8080,
  apiVersion: 'v1',
);

void main() {
  late FakeServerRepository repository;
  late InMemoryPreferencesStorage preferences;
  late SettingsRepository settings;

  ServerManager buildManager({FakeDiscoveryTransport? transport}) =>
      ServerManager(
        serverRepository: repository,
        settingsRepository: settings,
        discoveryService: DiscoveryService(
          transport: transport ?? FakeDiscoveryTransport(),
          tuning: const DiscoveryTuning(
            probeInterval: Duration(milliseconds: 5),
            probeTimeout: Duration(milliseconds: 10),
            probeRounds: 1,
          ),
        ),
      );

  setUp(() {
    repository = FakeServerRepository();
    preferences = InMemoryPreferencesStorage();
    settings = SettingsRepositoryImpl(storage: preferences);
  });

  group('发现结果转换', () {
    test('发现响应转换为档案（包含能力与版本）', () {
      final profile = ServerManager.profileFromDiscovery(
        const DiscoveryResponse(
          protocol: DiscoveryConstants.protocol,
          version: 1,
          service: DiscoveryConstants.service,
          serverId: 'srv-a',
          name: '客厅 AMMDS',
          host: '192.168.1.20',
          port: 9000,
          apiVersion: 'v1',
          versionName: '1.2.3',
          capabilities: <String, bool>{'media': true},
        ),
      );
      expect(profile.id, 'srv-a');
      expect(profile.name, '客厅 AMMDS');
      expect(profile.displayAddress, 'http://192.168.1.20:9000');
      expect(profile.serverVersion, '1.2.3');
      expect(profile.capabilities['media'], isTrue);
    });

    test('https 服务端使用 https 协议', () {
      final profile = ServerManager.profileFromDiscovery(
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
      expect(profile.protocol, 'https');
      expect(profile.isHttps, isTrue);
    });
  });

  group('手动配置', () {
    test('合法地址生成档案', () {
      final profile = ServerManager.profileFromManualInput(
        address: '192.168.1.100:8080',
      )!;
      expect(profile.host, '192.168.1.100');
      expect(profile.port, 8080);
      expect(profile.protocol, 'http');
      expect(profile.id, 'http://192.168.1.100:8080');
    });

    test('带名称与 https', () {
      final profile = ServerManager.profileFromManualInput(
        address: 'https://ammds.example.com',
        name: '  机房服务器  ',
      )!;
      expect(profile.name, '机房服务器');
      expect(profile.protocol, 'https');
      expect(profile.port, 443);
    });

    test('非法地址返回 null', () {
      expect(ServerManager.profileFromManualInput(address: '   '), isNull);
      expect(ServerManager.profileFromManualInput(address: 'ftp://x'), isNull);
    });
  });

  group('发现', () {
    test('发现结果会被保存为档案并回调上报', () async {
      final transport = FakeDiscoveryTransport(
        replies: <DiscoveryResponse>[
          const DiscoveryResponse(
            protocol: DiscoveryConstants.protocol,
            version: 1,
            service: DiscoveryConstants.service,
            serverId: 'found-1',
            name: 'Found Server',
            host: '192.168.1.77',
            port: 8080,
            apiVersion: 'v1',
          ),
        ],
      );
      final manager = buildManager(transport: transport);
      addTearDown(manager.dispose);

      final seen = <ServerProfile>[];
      final found = await manager.discover(onServerFound: seen.add);

      expect(found, hasLength(1));
      expect(found.single.id, 'found-1');
      expect(seen, hasLength(1));
      expect(manager.profiles, hasLength(1));
      expect(await settings.readServerProfiles(), hasLength(1));
    });

    test('未发现服务端时状态为 unavailable', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      final states = <ServerConnectionState>[];
      final subscription = manager.connectionStream.listen(states.add);
      addTearDown(subscription.cancel);

      await manager.discover();
      await Future<void>.delayed(Duration.zero);

      expect(states.first, ServerConnectionState.connecting);
      expect(states.last, ServerConnectionState.unavailable);
    });

    test('正在发现时重复调用直接返回空结果', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      final first = manager.discover();
      final second = await manager.discover();
      expect(second, isEmpty);
      await first;
    });

    test('已保存的服务端地址会作为单播目标参与发现', () async {
      // 「广播被丢弃、单播能通」的网络里，点名探测此前连过的地址才能重新发现服务端。
      final transport = FakeDiscoveryTransport();
      final manager = buildManager(transport: transport);
      addTearDown(manager.dispose);

      await manager.saveServer(_discovered, makeActive: true);
      await manager.discover();

      expect(transport.knownHosts, contains('192.168.1.50'));
      expect(transport.probeTargets, contains('192.168.1.50'));
    });

    test('没有任何已保存档案时不登记单播目标（首次使用只能靠广播）', () async {
      final transport = FakeDiscoveryTransport();
      final manager = buildManager(transport: transport);
      addTearDown(manager.dispose);

      await manager.discover();

      expect(transport.knownHosts, isEmpty);
    });
  });

  group('持续发现', () {
    test('后加入的监听者能收到此前已发现的服务端', () async {
      final transport = FakeDiscoveryTransport(
        replies: <DiscoveryResponse>[
          const DiscoveryResponse(
            protocol: DiscoveryConstants.protocol,
            version: 1,
            service: DiscoveryConstants.service,
            serverId: 'lan-1',
            name: '局域网服务端',
            host: '192.168.1.20',
            port: 8080,
            apiVersion: 'v1',
          ),
        ],
      );
      final manager = buildManager(transport: transport);
      addTearDown(manager.dispose);

      // 登录页先启动持续发现。
      final loginSeen = <ServerProfile>[];
      await manager.startWatching(onServerFound: loginSeen.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(loginSeen.map((profile) => profile.id), <String>['lan-1']);

      // 服务端选择页随后打开：它错过了「发现」发生的那一刻，
      // 但必须立刻拿到已有结果，而不是显示空列表。
      final selectSeen = <ServerProfile>[];
      await manager.startWatching(onServerFound: selectSeen.add);
      expect(selectSeen.map((profile) => profile.id), <String>['lan-1']);

      // 「重新搜索」在没有新服务端时同样刷新结果。
      selectSeen.clear();
      await manager.probeNow();
      expect(selectSeen.map((profile) => profile.id), <String>['lan-1']);
    });

    test('发现到的服务端未通过健康检查时不通知监听者也不保存', () async {
      final transport = FakeDiscoveryTransport(
        replies: <DiscoveryResponse>[
          const DiscoveryResponse(
            protocol: DiscoveryConstants.protocol,
            version: 1,
            service: DiscoveryConstants.service,
            serverId: 'unhealthy',
            name: '不可达服务端',
            host: '10.0.0.99',
            port: 8080,
            apiVersion: 'v1',
          ),
        ],
      );
      repository.probeError = NetworkError('server unreachable');
      final manager = buildManager(transport: transport);
      addTearDown(manager.dispose);

      final seen = <ServerProfile>[];
      await manager.startWatching(onServerFound: seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 健康检查失败：监听者收不到任何回调，档案也不被持久化。
      expect(seen, isEmpty);
      expect(repository.probeCalls, greaterThan(0));
      expect(manager.profiles, isEmpty);
      expect(await settings.readServerProfiles(), isEmpty);
    });

    test('Docker 自报内网 IP 时优先用 datagram 源地址通过验证', () async {
      // 服务端跑在 Docker 容器内：UDP 应答里 host 字段是容器内网 IP，
      // 但 datagram 源地址是宿主机局域网 IP（客户端实际能访问的地址）。
      final transport = FakeDiscoveryTransport(
        replies: <DiscoveryResponse>[
          const DiscoveryResponse(
            protocol: DiscoveryConstants.protocol,
            version: 1,
            service: DiscoveryConstants.service,
            serverId: 'docker-host',
            name: 'Docker 上的 AMMDS',
            host: '172.17.0.2',
            port: 8080,
            apiVersion: 'v1',
            sourceAddress: '192.168.1.30',
          ),
        ],
      );
      final manager = buildManager(transport: transport);
      addTearDown(manager.dispose);

      final seen = <ServerProfile>[];
      await manager.startWatching(onServerFound: seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 健康检查通过的候选必须是 datagram 源地址，而不是容器内网 IP。
      expect(seen, hasLength(1));
      expect(seen.single.host, '192.168.1.30');
      expect(seen.single.port, 8080);
      expect(manager.profiles.single.host, '192.168.1.30');
    });

    test('connect 失败时不进入 connected 状态并抛出', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      repository.probeError = NetworkError('connection refused');
      await expectLater(
        manager.connect(_discovered),
        throwsA(isA<ServerError>()),
      );
      expect(manager.connectionState, ServerConnectionState.unavailable);
      // 失败时不应保存为 active。
      expect(manager.activeServer?.id, isNot(_discovered.id));
    });
  });

  group('档案持久化', () {
    test('saveServer 持久化并激活', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      await manager.saveServer(_discovered, makeActive: true);
      expect(manager.profiles, hasLength(1));
      expect(manager.activeServer?.id, _discovered.id);
      expect(await settings.readActiveServerId(), _discovered.id);
    });

    test('重复保存同一 id 会更新而不是追加', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      await manager.saveServer(_discovered);
      await manager.saveServer(_discovered.copyWith(name: '改名'));
      expect(manager.profiles, hasLength(1));
      expect(manager.profiles.single.name, '改名');
    });

    test('removeServer 移除档案并清理当前服务器', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      await manager.saveServer(_discovered, makeActive: true);
      await manager.removeServer(_discovered.id);
      expect(manager.profiles, isEmpty);
      expect(manager.activeServer, isNull);
      expect(await settings.readActiveServerId(), isNull);
    });

    test('load 从本地配置恢复档案与当前服务器', () async {
      final first = buildManager();
      addTearDown(first.dispose);
      await first.saveServer(_discovered, makeActive: true);

      final restored = buildManager();
      addTearDown(restored.dispose);
      await restored.load();

      expect(restored.profiles, hasLength(1));
      expect(restored.activeServer?.id, _discovered.id);
    });

    test('发现到的网关类地址不会改写已连接成功的好地址', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      // 用户已连接成功：档案里是回环地址
      await manager.saveServer(
        const ServerProfile(
          id: 'test-server-0001',
          name: 'AMMDS Test Server',
          host: '127.0.0.1',
          port: 8080,
        ),
        makeActive: true,
      );

      // 之后服务端通过另一个网卡（热点 / ICS 网关）应答，host 变成 192.168.137.1
      await manager.saveServer(
        const ServerProfile(
          id: 'test-server-0001',
          name: 'AMMDS Test Server',
          host: '192.168.137.1',
          port: 8080,
        ),
      );

      expect(manager.profiles, hasLength(1));
      expect(manager.profiles.single.host, '127.0.0.1');
    });

    test('没有历史地址时网关类地址仍会被记录', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      await manager.saveServer(
        const ServerProfile(
          id: 'test-server-0002',
          name: 'AMMDS Test Server',
          host: '192.168.137.1',
          port: 8081,
        ),
      );

      expect(manager.profiles.single.host, '192.168.137.1');
    });
  });

  group('连接测试（文档 #58）', () {
    test('成功时返回 success 与服务端信息', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      final result = await manager.testConnection(_discovered);
      expect(result.success, isTrue);
      expect(result.serverVersion, '1.0.0');
      expect(result.apiVersion, 'v1');
      expect(manager.connectionState, ServerConnectionState.connected);
    });

    test('连接被拒绝时区分原因', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      repository.probeError = NetworkError(
        'connection refused',
        cause: const SocketException(
          'connection refused',
          osError: OSError('refused', 10061),
        ),
      );
      final result = await manager.testConnection(_discovered);
      expect(result.success, isFalse);
      expect(result.reason, ConnectionFailureReason.serverRefused);
      expect(manager.connectionState, ServerConnectionState.unavailable);
    });

    test('未授权时标记 unauthorized', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      repository.probeError = const AuthError('unauthorized');
      final result = await manager.testConnection(_discovered);
      expect(result.reason, ConnectionFailureReason.unauthorized);
      expect(manager.connectionState, ServerConnectionState.unauthorized);
    });

    test('超时归类为服务端不可达', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      repository.probeError = const TimeoutError('timeout');
      final result = await manager.testConnection(_discovered);
      expect(result.reason, ConnectionFailureReason.serverNotFound);
    });

    test('DNS 解析失败归类为服务端不存在', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      repository.probeError = NetworkError(
        'failed host lookup',
        cause: const SocketException('Failed host lookup'),
      );
      final result = await manager.testConnection(_discovered);
      expect(result.reason, ConnectionFailureReason.serverNotFound);
    });
  });

  group('connect 与切换', () {
    test('连接成功后保存并激活服务端', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      final connected = await manager.connect(_discovered);
      expect(connected.serverVersion, '1.0.0');
      expect(manager.activeServer?.id, _discovered.id);
      expect(manager.connectionState, ServerConnectionState.connected);
      expect(await settings.readActiveServerId(), _discovered.id);
    });

    test('disconnect 清除当前服务端', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      await manager.connect(_discovered);
      await manager.disconnect();
      expect(manager.activeServer, isNull);
      expect(manager.connectionState, ServerConnectionState.disconnected);
    });
  });
}
