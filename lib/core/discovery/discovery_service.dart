import 'dart:async';

import '../constants/discovery_constants.dart';
import '../logging/app_logger.dart';
import 'discovery_codec.dart';
import 'discovery_models.dart';
import 'discovery_transport.dart';

/// 发现节奏配置（文档 #17.2）。
///
/// 默认值来自协议常量；测试可以注入更短的节奏，
/// 从而在不等待真实探测窗口的情况下验证完整流程。
final class DiscoveryTuning {
  /// 创建节奏配置。
  const DiscoveryTuning({
    this.probeTimeout = DiscoveryConstants.probeTimeout,
    this.probeInterval = DiscoveryConstants.probeInterval,
    this.probeRounds = DiscoveryConstants.probeRounds,
    this.port = DiscoveryConstants.port,
    this.announcePort = DiscoveryConstants.announcePort,
  });

  /// 单次探测超时。
  final Duration probeTimeout;

  /// 探测间隔。
  final Duration probeInterval;

  /// 探测轮次。
  final int probeRounds;

  /// UDP 探测目标端口。
  final int port;

  /// 本地绑定端口（用于接收服务端周期广播与探测应答）。
  final int announcePort;
}

/// 服务发现服务（文档 #16 / #17.2 / #80）。
///
/// 采用「短时间多次探测」而不是一次长时间阻塞：
///
/// ```text
/// Start Discovery
///       ├── 立即发送请求
///       ├── 延迟重试（probeRounds 轮）
///       └── 超时结束
/// ```
///
/// 期间收到的每个响应都会被校验、回退 host 并去重；
/// 非法响应与协议不兼容的响应只记日志，不中断发现过程。
final class DiscoveryService {
  /// 创建发现服务。
  DiscoveryService({
    DiscoveryTransport? transport,
    DiscoveryTuning tuning = const DiscoveryTuning(),
  }) : _transport = transport ?? UdpDiscoveryTransport(),
       _probeTimeout = tuning.probeTimeout,
       _probeInterval = tuning.probeInterval,
       _probeRounds = tuning.probeRounds,
       _port = tuning.port,
       _announcePort = tuning.announcePort;

  final DiscoveryTransport _transport;

  /// 单次探测超时。
  final Duration _probeTimeout;

  /// 探测间隔。
  final Duration _probeInterval;

  /// 探测轮次。
  final int _probeRounds;

  /// UDP 发现端口。
  final int _port;

  /// 本地绑定端口（接收广播与应答）。
  final int _announcePort;

  bool _running = false;

  /// 是否正在发现中。
  bool get isRunning => _running;

  /// 传输层是否成功绑定了广播端口（可接收服务端主动广播）。
  bool get receivesBroadcast => _transport.receivesBroadcast;

  /// 当前平台的发现能力是否可用（Web 端为 false，见 [DiscoveryTransport.isSupported]）。
  bool get isSupported => _transport.isSupported;

  /// 把「已知服务端地址」交给传输层做**单播**探测。
  ///
  /// 广播在企业 Wi-Fi、Mesh、部分路由器策略下会被丢弃，单播往往仍然通；
  /// 点名探测用户已保存过的地址，这些网络里也能重新发现服务端。
  /// 由 ServerManager 在开始发现前调用（它持有已保存的档案）。
  void useKnownHosts(Iterable<String> hosts) => _transport.useKnownHosts(hosts);

  /// 创建「持续发现」监听器（文档 #17.2：服务端定期广播 + 客户端主动探测）。
  ///
  /// 与一次性的 [discover] 互斥：同一传输在任一时刻只能有一种模式在运行。
  DiscoveryWatcher watch({
    Duration reprobeInterval = DiscoveryConstants.watchProbeInterval,
  }) => DiscoveryWatcher(
    service: this,
    reprobeInterval: reprobeInterval,
  );

  /// 执行一次发现。
  ///
  /// [port] 为 UDP 发现端口（默认取构造时的配置）；
  /// [onServerFound] 在每个新服务端被发现时回调，便于 UI 增量刷新列表（文档 #57）。
  Future<DiscoveryOutcome> discover({
    int? port,
    void Function(DiscoveryResponse server)? onServerFound,
  }) async {
    final effectivePort = port ?? _port;
    if (_running) {
      throw StateError('Discovery is already running');
    }
    _running = true;
    final found = <String, DiscoveryResponse>{};
    var invalid = 0;
    Object? failure;
    var rounds = 0;
    var timedOut = false;

    try {
      await _transport.open(
        probePort: effectivePort,
        announcePort: _announcePort,
      );
      final subscription = _transport.responses.listen((datagram) {
        try {
          final response = DiscoveryCodec.decodeResponse(
            datagram.bytes,
            sourceAddress: datagram.sourceAddress,
          );
          if (found.containsKey(response.dedupeKey)) {
            AppLogger.debug(
              'DiscoveryService',
              'duplicate response from ${response.displayAddress} ignored',
            );
            return;
          }
          found[response.dedupeKey] = response;
          AppLogger.info(
            'DiscoveryService',
            'discovered ${response.name} at ${response.displayAddress}',
          );
          onServerFound?.call(response);
        } on DiscoveryProtocolException catch (error) {
          invalid++;
          AppLogger.debug(
            'DiscoveryService',
            'invalid discovery response from ${datagram.sourceAddress}: '
                '${error.code} ${error.message}',
          );
        } on Object catch (error) {
          invalid++;
          AppLogger.debug(
            'DiscoveryService',
            'failed to handle discovery response: '
                '${AppLogger.sanitize('$error')}',
          );
        }
      });

      final payload = DiscoveryCodec.encodeRequest(const DiscoveryRequest());
      for (var round = 0; round < _probeRounds; round++) {
        rounds = round + 1;
        try {
          await _transport.sendProbe(payload);
        } on Object catch (error) {
          failure = error;
          AppLogger.warning('DiscoveryService', 'probe round failed', error);
        }
        await Future<void>.delayed(_probeInterval);
      }
      // 最后一轮之后再等待一个探测窗口，收集迟到响应。
      await Future<void>.delayed(_probeTimeout);
      timedOut = true;
      await subscription.cancel();
    } on Object catch (error) {
      failure = error;
      AppLogger.warning('DiscoveryService', 'discovery failed', error);
    } finally {
      await _transport.close();
      _running = false;
    }

    return DiscoveryOutcome(
      servers: found.values.toList(growable: false),
      invalidResponses: invalid,
      rounds: rounds,
      timedOut: timedOut,
      error: failure,
    );
  }

  /// 释放资源。
  Future<void> dispose() => _transport.close();
}

/// 持续发现监听器（文档 #17.2「同时支持两种模式：广播和响应」）。
///
/// 与一次性的 [DiscoveryService.discover] 不同，本模式在页面存活期间长期运行：
///
/// * 绑定广播端口，**被动接收**服务端周期广播 —— 解决「App 打开时服务端已在线」；
/// * 周期性**主动探测** —— 解决「服务端刚启动，还没到下一次广播时间点」。
///
/// 两者共用同一套套接字与去重逻辑，因此同一服务端无论通过哪条路径被发现都只保留一次。
/// 发现过程不设总超时：服务端随时上线都能被补充进列表，直到调用方主动 [stop]。
final class DiscoveryWatcher {
  /// 创建监听器。
  DiscoveryWatcher({
    required this._service,
    this.reprobeInterval = DiscoveryConstants.watchProbeInterval,
  });

  final DiscoveryService _service;

  /// 主动探测间隔。
  final Duration reprobeInterval;

  final Map<String, DiscoveryResponse> _found = <String, DiscoveryResponse>{};
  StreamSubscription<DiscoveryDatagram>? _subscription;
  Timer? _timer;
  bool _running = false;
  int _invalidResponses = 0;

  /// 发现新服务端时的回调（增量刷新列表）。
  void Function(DiscoveryResponse server)? onServerFound;

  /// 是否正在监听。
  bool get isRunning => _running;

  /// 已发现的服务端（按 server_id 去重，禁用 IP 判定同一服务端）。
  List<DiscoveryResponse> get servers => _found.values.toList(growable: false);

  /// 被忽略的非法响应数量。
  int get invalidResponses => _invalidResponses;

  /// 是否已绑定广播端口（绑定失败时只能靠主动探测）。
  bool get receivesBroadcast => _service._transport.receivesBroadcast;

  /// 本地绑定端口。
  int get boundPort => _service._transport.boundPort;

  /// 开始监听：绑定端口 → 立即探测一次 → 按 [reprobeInterval] 持续探测。
  Future<void> start() async {
    if (_running) {
      return;
    }
    _running = true;
    try {
      await _service._transport.open(
        probePort: _service._port,
        announcePort: _service._announcePort,
      );
      _subscription = _service._transport.responses.listen(_handleDatagram);
      await _sendProbe();
      _timer = Timer.periodic(reprobeInterval, (_) => _sendProbe());
    } on Object {
      _running = false;
      await stop();
      rethrow;
    }
  }

  /// 停止监听并释放套接字。
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await _service._transport.close();
  }

  /// 立即补发一次探测（用于界面上的「重新搜索」）。
  Future<void> probeNow() => _sendProbe();

  /// 发送一次探测，失败只记日志（下一次周期仍会重试）。
  Future<void> _sendProbe() async {
    try {
      await _service._transport.sendProbe(
        DiscoveryCodec.encodeRequest(const DiscoveryRequest()),
      );
    } on Object catch (error) {
      AppLogger.warning('DiscoveryWatcher', 'probe round failed', error);
    }
  }

  void _handleDatagram(DiscoveryDatagram datagram) {
    try {
      final response = DiscoveryCodec.decodeResponse(
        datagram.bytes,
        sourceAddress: datagram.sourceAddress,
      );
      if (_found.containsKey(response.dedupeKey)) {
        return;
      }
      _found[response.dedupeKey] = response;
      AppLogger.info(
        'DiscoveryWatcher',
        'discovered ${response.name} at ${response.displayAddress} '
            '(${response.isAnnounce ? 'announce' : 'reply'})',
      );
      onServerFound?.call(response);
    } on DiscoveryProtocolException catch (error) {
      _invalidResponses++;
      AppLogger.debug(
        'DiscoveryWatcher',
        'invalid discovery datagram from ${datagram.sourceAddress}: '
            '${error.code} ${error.message}',
      );
    } on Object catch (error) {
      _invalidResponses++;
      AppLogger.debug(
        'DiscoveryWatcher',
        'failed to handle discovery datagram: '
            '${AppLogger.sanitize('$error')}',
      );
    }
  }
}
