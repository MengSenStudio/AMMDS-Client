import 'dart:async';

import '../../core/constants/discovery_constants.dart';
import '../../core/discovery/discovery_models.dart';
import '../../core/discovery/discovery_service.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/server.dart';
import '../../domain/repositories/repositories.dart';

/// 服务端管理器（文档 #90 / #53 / #90）。
///
/// 统一负责：
/// * `discover()`：局域网自动发现
/// * `connect()` / `disconnect()`：当前服务端切换
/// * `testConnection()`：手动地址连通性测试
/// * `saveServer()` / `removeServer()`：档案持久化
final class ServerManager {
  /// 创建管理器。
  ServerManager({
    required this.serverRepository,
    required this.settingsRepository,
    required this.discoveryService,
  });

  /// 需要跳过的「伪服务端」主机地址。
  ///
  /// `192.168.137.1` 是 Windows 移动热点 / Internet 连接共享（ICS）给网卡分配的
  /// 网关地址。它既可能是热点网关上无关的响应，也可能是**本机服务端在该网卡上的
  /// 地址**（UDP 探测应答的 host 取自报文来源网卡），因此这里**只在展示层过滤**，
  /// 不能在发现层丢弃：一旦丢弃，本机部署下会连真实服务端一起找不到。
  ///
  /// 注意：回环地址 `127.0.0.1` / `localhost` 是**受支持**的，不在此列。
  static const Set<String> ignoredHosts = <String>{'192.168.137.1'};

  /// 该主机是否属于「搜索列表中不展示」的地址。
  static bool isIgnoredHost(String host) => ignoredHosts.contains(host.trim());

  /// 服务端仓库。
  final ServerRepository serverRepository;

  /// 设置仓库（档案持久化）。
  final SettingsRepository settingsRepository;

  /// 发现服务。
  final DiscoveryService discoveryService;

  final StreamController<ServerConnectionState> _connectionController =
      StreamController<ServerConnectionState>.broadcast();

  /// 当前服务端变更流。
  ///
  /// 界面（登录页预填地址、管理页展示「当前服务器」）必须能感知切换结果，
  /// 因此每次 [_active] 变化都会推送一次。
  final StreamController<ServerProfile?> _activeController =
      StreamController<ServerProfile?>.broadcast();

  ServerConnectionState _connectionState = ServerConnectionState.disconnected;
  List<ServerProfile> _profiles = const <ServerProfile>[];
  ServerProfile? _active;
  bool _discovering = false;
  DiscoveryWatcher? _watcher;
  final Set<void Function(ServerProfile server)> _watchListeners =
      <void Function(ServerProfile server)>{};

  /// 已通过健康检查的服务端（按响应的 [DiscoveryResponse.serverId] 索引）。
  ///
  /// UDP 应答里的 `host` 字段是**服务端自报**的地址：当服务端跑在 Docker 容器
  /// 内时，自报的可能是容器内网 IP（如 `172.17.0.2`），客户端根本访问不到。
  /// 因此发现到的服务端必须先做一次 [ServerRepository.probe]（GET
  /// `/api/client/v1/health`）验证：通过才视为「有效服务端」推送给监听者
  /// 与持久化；不通过则丢弃，避免给用户一个连不上的地址却显示「连接成功」。
  ///
  /// 缓存键是 [DiscoveryResponse.serverId]：同一服务端在多个网卡下应答
  /// （host 不同但 server_id 相同）只验证一次；不同的 server_id 分别验证。
  final Map<String, ServerProfile> _verifiedServers =
      <String, ServerProfile>{};

  /// 正在验证中的 server_id，避免同一服务端被并发重复探测。
  final Set<String> _verifyingIds = <String>{};

  /// 连接状态流。
  Stream<ServerConnectionState> get connectionStream =>
      _connectionController.stream;

  /// 当前服务端变更流。
  ///
  /// 新订阅者会**立即收到当前值**，避免界面在订阅后到首次推送之间处于「无服务端」状态。
  Stream<ServerProfile?> get activeServerStream async* {
    yield _active;
    yield* _activeController.stream;
  }

  /// 当前连接状态。
  ServerConnectionState get connectionState => _connectionState;

  /// 已保存的档案。
  List<ServerProfile> get profiles => List.unmodifiable(_profiles);

  /// 当前服务端。
  ServerProfile? get activeServer => _active;

  /// 是否正在发现。
  bool get isDiscovering => _discovering;

  /// 是否正在持续发现（服务端广播 + 客户端主动探测）。
  bool get isWatching => _watcher?.isRunning ?? false;

  /// 传输层是否成功绑定了广播端口（可接收服务端主动广播）。
  bool get receivesBroadcast => discoveryService.receivesBroadcast;

  /// 当前平台的局域网发现能力是否可用。
  ///
  /// Web 端浏览器沙箱不支持 UDP，返回 false；界面据此提示用户手填服务端地址，
  /// 而不是展示一个永远不会出结果的「搜索中」。
  bool get discoverySupported => discoveryService.isSupported;

  /// 从本地配置载入档案（文档 #43）。
  Future<void> load() async {
    _profiles = await settingsRepository.readServerProfiles();
    final activeId = await settingsRepository.readActiveServerId();
    if (activeId != null) {
      for (final profile in _profiles) {
        if (profile.id == activeId) {
          _active = profile;
          break;
        }
      }
    }
    _active ??= _profiles.isEmpty ? null : _profiles.first;
    _emitActive();
    AppLogger.info(
      'ServerManager',
      'loaded ${_profiles.length} server profile(s), '
          'active=${_active?.displayAddress ?? 'none'}',
    );
  }

  /// 局域网发现（文档 #16 / #17.2 / #57）。
  ///
  /// 增量回调 [onServerFound] 让 UI 边发现边展示。每个服务端在回调前都会
  /// 先经过 [_verifyDiscovery] 健康检查：未通过验证的服务端会被丢弃，
  /// 不会出现在结果列表里，也不会被保存。
  Future<List<ServerProfile>> discover({
    void Function(ServerProfile server)? onServerFound,
  }) async {
    if (_discovering) {
      return const <ServerProfile>[];
    }
    _discovering = true;
    _setConnectionState(ServerConnectionState.connecting);
    final merged = <String, ServerProfile>{};
    try {
      _registerKnownHosts();
      await discoveryService.discover(
        port: DiscoveryConstants.port,
        onServerFound: (response) {
          unawaited(
            _verifyAndAdopt(response).then((profile) {
              if (profile == null) {
                return;
              }
              merged[profile.id] = profile;
              onServerFound?.call(profile);
            }),
          );
        },
      );
    } on Object catch (error) {
      AppLogger.warning('ServerManager', 'discovery failed', error);
    } finally {
      _discovering = false;
      if (merged.isEmpty) {
        _setConnectionState(ServerConnectionState.unavailable);
      }
    }
    final found = merged.values.toList(growable: false);
    if (found.isNotEmpty) {
      // 已保存的档案优先保留本地信息，避免覆盖用户重命名。
      for (final profile in found) {
        await saveServer(profile, makeActive: false);
      }
    }
    return found;
  }

  /// 把已保存的服务端地址登记为单播探测目标。
  ///
  /// 广播在部分网络（企业 Wi-Fi / Mesh / AP 隔离策略）里会被丢弃，单播通常仍然通；
  /// 点名探测用户此前连过的地址，可以在这类网络里重新发现服务端，
  /// 而不是只能手动输入。没有任何档案时什么都不做（首次使用本就只能靠广播）。
  void _registerKnownHosts() {
    final hosts = _profiles
        .map((profile) => profile.host)
        .where((host) => host.isNotEmpty)
        .toList(growable: false);
    if (hosts.isEmpty) {
      return;
    }
    discoveryService.useKnownHosts(hosts);
  }

  /// 开始「持续发现」（文档 #17.2：服务端定期广播 + 客户端主动探测）。
  ///
  /// 与 [discover] 的一次性探测不同，本模式会一直监听，直到所有监听者都
  /// [stopWatching]：服务端在任何时刻上线、或进入当前网络，都会在下一个探测周期内
  /// 被发现，因此登录页 / 服务端选择页不需要依赖「一次性扫描刚好命中」。
  ///
  /// 支持多个页面（例如登录页与其上方的服务端选择页）同时监听：
  /// 回调按监听者集合管理，谁先注册谁就能收到增量更新。
  ///
  /// 每个发现到的服务端都会先经过 [_verifyAndAdopt] 健康检查（GET
  /// `/api/client/v1/health`），通过的才推送给监听者：避免服务端自报了一个
  /// 客户端访问不到的地址（典型场景：Docker 容器内网 IP）却被显示成「已发现」
  /// 甚至在用户选择后显示「连接成功」。
  Future<void> startWatching({
    void Function(ServerProfile server)? onServerFound,
  }) async {
    if (onServerFound != null) {
      _watchListeners.add(onServerFound);
    }
    final running = _watcher;
    if (running != null && running.isRunning) {
      // 发现已经在运行（典型场景：登录页先启动发现，服务端选择页随后压栈）。
      // 后加入的监听者会错过此前已经发现的结果，于是选择页会一直显示空列表。
      // 这里把**已通过健康检查**的服务端补发给新监听者；未通过验证的不补发，
      // 因为它们根本访问不到。
      if (onServerFound != null) {
        for (final profile in _verifiedServers.values) {
          onServerFound(profile);
        }
      }
      return;
    }
    final watcher = discoveryService.watch();
    _registerKnownHosts();
    watcher.onServerFound = (response) {
      unawaited(_verifyAndAdopt(response).then((profile) {
        if (profile == null) {
          return;
        }
        _notifyWatchListeners(profile);
        // 落盘以便「服务端列表」与「上次使用的服务端」可用；失败不影响发现流程。
        unawaited(saveServer(profile, makeActive: false));
      }));
    };
    _watcher = watcher;
    _setConnectionState(ServerConnectionState.connecting);
    try {
      await watcher.start();
    } on Object catch (error) {
      _watcher = null;
      _watchListeners.remove(onServerFound);
      _setConnectionState(ServerConnectionState.unavailable);
      AppLogger.warning('ServerManager', 'start watching failed', error);
      rethrow;
    }
  }

  /// 停止监听。
  ///
  /// [listener] 为注册时的回调：仅移除该监听者；全部监听者都移除后才会真正
  /// 关闭 UDP 套接字。[listener] 为空表示强制停止全部监听。
  ///
  /// 停止时不会自动把连接状态设为 `connected`：UDP 应答的存在只代表「网内
  /// 有响应」，不等于「客户端用响应里的地址能访问到服务端」（Docker 容器
  /// 自报内网 IP 就是反例）。真正的「连接成功」只发生在 [connect] /
  /// [testConnection] 成功之后。
  Future<void> stopWatching({void Function(ServerProfile server)? listener}) async {
    if (listener != null) {
      _watchListeners.remove(listener);
    } else {
      _watchListeners.clear();
    }
    if (_watchListeners.isNotEmpty) {
      return;
    }
    final watcher = _watcher;
    _watcher = null;
    if (watcher == null) {
      return;
    }
    await watcher.stop();
    // 缓存清空：下一次启动监听时重新做健康检查，避免拿过期的「上次还能连」
    // 去直接补发给新监听者（服务端可能已经下线或换地址）。
    _verifiedServers.clear();
    _verifyingIds.clear();
  }

  /// 立即补发一次探测（供界面上的「重新搜索」使用）。
  ///
  /// 持续发现本身会周期探测，本方法只用于让用户的手动操作得到即时反馈。
  /// 探测之后会把**当前已通过健康检查**的服务端重新通知一遍：网内服务端
  /// 没有变化时本轮探测不会产生新的回调，但界面仍需要一次结果刷新。
  Future<void> probeNow() async {
    final watcher = _watcher;
    if (watcher == null) {
      return;
    }
    await watcher.probeNow();
    // watcher.servers 是原始 DiscoveryResponse 列表；只补发已通过健康检查的。
    // 新响应由 watcher.onServerFound 异步触发健康检查再走通知流程。
    for (final response in watcher.servers) {
      final verified = _verifiedServers[response.serverId];
      if (verified != null) {
        _notifyWatchListeners(verified);
      }
    }
  }

  /// 把发现响应转换成通过健康检查的 [ServerProfile]。
  ///
  /// 候选 host 按以下顺序去重并尝试（[ignoredHosts] 直接过滤）：
  /// 1. UDP 应答的 [DiscoveryResponse.sourceAddress]（datagram 源地址）——
  ///    这是客户端实际能看到的网络源地址，Docker 容器场景下通常是宿主机 IP；
  /// 2. 服务端自报的 [DiscoveryResponse.host]——服务端可能自报了公网域名 / IP，
  ///    datagram 源地址只是 NAT 后的内网地址，公网自报才是可访问的。
  ///
  /// 第一个 [ServerRepository.probe]（GET `/api/client/v1/health`）通过的候选
  /// 即被采纳为该服务端的最终 host，并写回 [_verifiedServers] 缓存；
  /// 全部失败返回 `null`，调用方据此丢弃该响应（不通知监听者、不保存档案）。
  ///
  /// 同一 [DiscoveryResponse.serverId] 并发触发时只验证一次：第二次起直接
  /// 命中缓存返回；如果首次还在进行中，第二次会被 [_verifyingIds] 挡掉返回 `null`，
  /// 后续 `probeNow` / 重启监听可以重新触发验证。
  Future<ServerProfile?> _verifyAndAdopt(DiscoveryResponse response) async {
    final cached = _verifiedServers[response.serverId];
    if (cached != null) {
      return cached;
    }
    if (_verifyingIds.contains(response.serverId)) {
      return null;
    }
    _verifyingIds.add(response.serverId);
    try {
      final verified = await _verifyDiscovery(response);
      if (verified != null) {
        _verifiedServers[response.serverId] = verified;
      }
      return verified;
    } finally {
      _verifyingIds.remove(response.serverId);
    }
  }

  /// 在多个候选 host 上做健康检查，返回第一个通过的 [ServerProfile]。
  ///
  /// 候选列表按 [_verifyAndAdopt] 注释中的优先级构造：datagram 源地址优先
  /// （Docker 容器场景下通常源地址才可达），其次服务端自报值。两个值相同
  /// 时只试一次；地址全部被 [ignoredHosts] 过滤时返回 `null`。
  Future<ServerProfile?> _verifyDiscovery(DiscoveryResponse response) async {
    final candidates = <String>[];
    void addCandidate(String? host) {
      final value = host?.trim();
      if (value == null || value.isEmpty) {
        return;
      }
      if (isIgnoredHost(value)) {
        return;
      }
      if (candidates.contains(value)) {
        return;
      }
      candidates.add(value);
    }
    // 优先 datagram 源地址（客户端实际能看到的网络源）：
    // Docker 容器内服务端自报的 host 通常是 172.x 内网 IP，但 datagram
    // 源地址是宿主机局域网 IP，后者才是客户端能访问到的。
    addCandidate(response.sourceAddress);
    addCandidate(response.host);
    if (candidates.isEmpty) {
      return null;
    }
    for (final host in candidates) {
      final candidate = ServerProfile(
        id: ServerProfile.deriveId(
          protocol: response.protocolName,
          host: host,
          port: response.port,
          serverId: response.serverId,
        ),
        name: response.name,
        host: host,
        port: response.port,
        protocol: response.protocolName,
        apiVersion: response.apiVersion,
        serverVersion: response.versionName,
        capabilities: response.capabilities,
      );
      try {
        final verified = await serverRepository.probe(candidate);
        AppLogger.info(
          'ServerManager',
          'discovered server verified: '
              '${verified.displayAddress} (${response.serverId})',
        );
        return verified;
      } on Object catch (error) {
        AppLogger.debug(
          'ServerManager',
          'probe ${candidate.displayAddress} failed: '
              '${AppLogger.sanitize('$error')}',
        );
      }
    }
    return null;
  }

  /// 把发现结果通知给所有已注册的监听者。
  void _notifyWatchListeners(ServerProfile profile) {
    for (final listener in List.of(_watchListeners)) {
      listener(profile);
    }
  }

  static ServerProfile profileFromDiscovery(DiscoveryResponse response) =>
      ServerProfile(
        id: ServerProfile.deriveId(
          protocol: response.protocolName,
          host: response.host,
          port: response.port,
          serverId: response.serverId,
        ),
        name: response.name,
        host: response.host,
        port: response.port,
        protocol: response.protocolName,
        apiVersion: response.apiVersion,
        serverVersion: response.versionName,
        capabilities: response.capabilities,
      );

  /// 手动配置服务端（文档 #18）。
  ///
  /// 返回 `null` 表示地址格式非法。
  static ServerProfile? profileFromManualInput({
    required String address,
    String? name,
  }) {
    final parsed = ServerAddressInput.parse(address);
    if (parsed == null) {
      return null;
    }
    return ServerProfile(
      id: ServerProfile.deriveId(
        protocol: parsed.protocol,
        host: parsed.host,
        port: parsed.port,
      ),
      name: (name == null || name.trim().isEmpty)
          ? parsed.display
          : name.trim(),
      host: parsed.host,
      port: parsed.port,
      protocol: parsed.protocol,
    );
  }

  /// 测试连接（文档 #18 / #58）。
  Future<ConnectionCheckResult> testConnection(ServerProfile candidate) async {
    _setConnectionState(ServerConnectionState.connecting);
    try {
      final probe = await serverRepository.probe(candidate);
      _setConnectionState(ServerConnectionState.connected);
      return ConnectionCheckResult.success(
        serverVersion: probe.serverVersion,
        apiVersion: probe.apiVersion,
        capabilities: probe.capabilities,
      );
    } on Object catch (error) {
      final reason = classifyConnectionFailure(error);
      if (reason == ConnectionFailureReason.unauthorized) {
        _setConnectionState(ServerConnectionState.unauthorized);
      } else {
        _setConnectionState(ServerConnectionState.unavailable);
      }
      AppLogger.warning(
        'ServerManager',
        'connection test failed: ${reason.name}',
        error,
      );
      return ConnectionCheckResult.failure(reason, message: '$error');
    }
  }

  /// 连接并激活服务端。
  ///
  /// 先做 [testConnection]（GET `/api/client/v1/health`）：失败时**直接抛出**，
  /// 不继续 `fetchServerInfo`，避免拿着一个不可达的地址去请求根接口。
  /// 成功后才读取服务端信息、保存并激活。
  Future<ServerProfile> connect(ServerProfile candidate) async {
    final check = await testConnection(candidate);
    if (!check.success) {
      // testConnection 已经把连接状态置为 unavailable / unauthorized，
      // 这里抛出 AppException 让调用方给出错误反馈，而不是 toast「连接成功」。
      throw ServerError(
        check.message?.isNotEmpty == true ? check.message! : 'Connection failed',
        code: check.reason?.name,
      );
    }
    final info = await serverRepository.fetchServerInfo(candidate);
    await saveServer(info, makeActive: true);
    _active = info;
    _emitActive();
    _setConnectionState(ServerConnectionState.connected);
    return info;
  }

  /// 断开当前服务端。
  Future<void> disconnect() async {
    _active = null;
    await settingsRepository.writeActiveServerId(null);
    _emitActive();
    _setConnectionState(ServerConnectionState.disconnected);
  }

  /// 保存（或更新）服务端档案。
  Future<void> saveServer(
    ServerProfile profile, {
    bool makeActive = false,
  }) async {
    var incoming = profile;
    final existing = _findById(_profiles, profile.id);
    if (!makeActive && existing != null) {
      // 发现流程只做「元信息补充」：UDP 应答的 host 取自**报文来源网卡**，
      // 同一服务端可能时而报回环地址、时而报热点网关地址（如 192.168.137.1）。
      // 若该服务端已有可连接的地址，就不让网关类地址把它改写掉，
      // 否则用户下次启动会拿着一个连不上的地址去连接。
      if (isIgnoredHost(profile.host) && !isIgnoredHost(existing.host)) {
        incoming = profile.copyWith(host: existing.host, port: existing.port);
      }
    }
    final updated = <ServerProfile>[];
    var replaced = false;
    for (final item in _profiles) {
      if (item.id == incoming.id) {
        updated.add(incoming);
        replaced = true;
      } else {
        updated.add(item);
      }
    }
    if (!replaced) {
      updated.add(incoming);
    }
    _profiles = updated;
    await settingsRepository.saveServerProfiles(_profiles);
    if (makeActive || _active == null) {
      _active = incoming;
      await settingsRepository.writeActiveServerId(incoming.id);
      _emitActive();
    }
  }

  static ServerProfile? _findById(List<ServerProfile> profiles, String id) {
    for (final profile in profiles) {
      if (profile.id == id) {
        return profile;
      }
    }
    return null;
  }

  /// 移除服务端档案。
  Future<void> removeServer(String id) async {
    _profiles = _profiles
        .where((profile) => profile.id != id)
        .toList(growable: false);
    await settingsRepository.saveServerProfiles(_profiles);
    if (_active?.id == id) {
      _active = _profiles.isEmpty ? null : _profiles.first;
      await settingsRepository.writeActiveServerId(_active?.id);
      _emitActive();
    }
  }

  /// 释放资源。
  Future<void> dispose() async {
    await stopWatching();
    await _connectionController.close();
    await _activeController.close();
    await discoveryService.dispose();
  }

  /// 推送当前服务端变更。
  void _emitActive() {
    if (!_activeController.isClosed) {
      _activeController.add(_active);
    }
  }

  void _setConnectionState(ServerConnectionState state) {
    _connectionState = state;
    if (!_connectionController.isClosed) {
      _connectionController.add(state);
    }
  }
}
