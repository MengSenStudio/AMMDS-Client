import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../constants/discovery_constants.dart';
import '../errors/app_exception.dart';
import '../logging/app_logger.dart';
import 'discovery_transport.dart';

/// 基于 `dart:io` 的 UDP 广播发现传输（文档 #16.1 / #17.1）。
///
/// 同时支撑两种发现模式：
///
/// * **主动探测**：向受限广播、各网卡定向广播与本机回环地址发送探测，服务端逐条应答；
/// * **被动接收**：绑定 [DiscoveryConstants.announcePort]，直接接收服务端周期广播，
///   使「App 打开时服务端刚好已在线」也能立即出现在列表里。
///
/// 两种模式共用同一个套接字，因此探测应答（服务端回给本套接字端口）与周期广播
/// 都会被 [responses] 收到。
///
/// 该实现只能在 IO 平台编译（依赖 `dart:io`）；Web 端由
/// `discovery_transport_web.dart` 提供同名占位实现。
final class UdpDiscoveryTransport implements DiscoveryTransport {
  UdpDiscoveryTransport({
    this.additionalProbeTargets = const <String>[],
    this.enableBroadcast = true,
  });

  /// 额外探测目标（测试时用于注入）。
  final List<String> additionalProbeTargets;

  /// 已保存服务端的主机，作为单播探测目标（见 [useKnownHosts]）。
  ///
  /// 上限 [maxKnownHosts]：档案数量本就很少，设上限是防止异常输入导致探测目标膨胀。
  final Set<String> _knownHosts = <String>{};

  /// 已知主机数量上限。
  static const int maxKnownHosts = 8;

  /// 是否使用受限广播地址。
  final bool enableBroadcast;

  RawDatagramSocket? _socket;

  /// 报文流控制器。
  ///
  /// 非 final：套接字关闭后本对象需要支持**重新打开**
  /// （典型场景：退出登录回到登录页，同一个传输实例会被再次使用）。
  StreamController<DiscoveryDatagram> _controller =
      StreamController<DiscoveryDatagram>.broadcast();
  bool _closed = false;
  int _probePort = DiscoveryConstants.port;

  @override
  Stream<DiscoveryDatagram> get responses => _controller.stream;

  @override
  late List<String> probeTargets;

  @override
  int boundPort = 0;

  @override
  bool receivesBroadcast = false;

  @override
  bool get isSupported => true;

  @override
  Future<void> open({
    int? probePort,
    int? announcePort,
  }) async {
    _probePort = probePort ?? DiscoveryConstants.port;
    final preferred = announcePort ?? DiscoveryConstants.announcePort;
    _closed = false;
    if (_controller.isClosed) {
      _controller = StreamController<DiscoveryDatagram>.broadcast();
    }

    // 优先绑定广播端口以接收服务端主动广播；
    // 端口被占用（例如同机部署了服务端或已有另一个客户端实例）时回退为临时端口，
    // 此时仍能通过主动探测 + 应答完成发现。
    var socket = await _tryBind(preferred);
    receivesBroadcast = socket != null;
    if (socket == null) {
      AppLogger.info(
        'UdpDiscoveryTransport',
        'announce port $preferred unavailable, falling back to an ephemeral port',
      );
      socket = await _tryBind(0);
    }
    if (socket == null) {
      throw const NetworkError('Failed to bind UDP socket for discovery');
    }
    socket.broadcastEnabled = enableBroadcast;
    _socket = socket;
    boundPort = socket.port;
    if (Platform.isAndroid) {
      // 安卓 Wi-Fi 驱动默认过滤入向广播/组播报文，必须持有 MulticastLock
      // 才能正常接收服务端周期广播与探测应答。
      await _acquireMulticastLock();
    }
    final bound = socket;
    bound.listen(
      (event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final datagram = bound.receive();
        if (datagram == null || _closed) {
          return;
        }
        _controller.add(
          DiscoveryDatagram(
            bytes: datagram.data,
            sourceAddress: datagram.address.address,
            sourcePort: datagram.port,
          ),
        );
      },
      onError: (Object error) {
        AppLogger.warning('UdpDiscoveryTransport', 'socket error', error);
      },
      cancelOnError: false,
    );
    probeTargets = await _resolveProbeTargets();
    AppLogger.info(
      'UdpDiscoveryTransport',
      'UDP discovery bound to ${bound.address.address}:$boundPort '
          '(broadcast=${receivesBroadcast ? 'on' : 'off'}), '
          'probePort=$_probePort, targets=$probeTargets',
    );
  }

  /// 尝试绑定指定端口，失败返回 null 而不抛出。
  Future<RawDatagramSocket?> _tryBind(int port) async {
    try {
      return await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
    } on Object catch (error) {
      AppLogger.debug(
        'UdpDiscoveryTransport',
        'bind port $port failed: ${AppLogger.sanitize('$error')}',
      );
      return null;
    }
  }

  Future<List<String>> _resolveProbeTargets() async {
    final targets = <String>{};
    if (enableBroadcast) {
      targets.add(DiscoveryConstants.broadcastAddress);
    }
    targets.add(DiscoveryConstants.loopbackProbeAddress);
    targets.addAll(additionalProbeTargets);
    targets.addAll(_knownHosts);
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final subnetBroadcast = _subnetBroadcastAddress(address.address);
          if (subnetBroadcast != null) {
            targets.add(subnetBroadcast);
          }
        }
      }
    } on Object catch (error) {
      AppLogger.warning(
        'UdpDiscoveryTransport',
        'failed to enumerate network interfaces',
        error,
      );
    }
    return targets.toList(growable: false);
  }

  static const MethodChannel _multicastChannel = MethodChannel(
    'ammds/discovery/multicast_lock',
  );

  Future<void> _acquireMulticastLock() async {
    try {
      await _multicastChannel.invokeMethod('acquire');
    } on Object catch (error) {
      AppLogger.warning(
        'UdpDiscoveryTransport',
        'failed to acquire multicast lock',
        error,
      );
    }
  }

  Future<void> _releaseMulticastLock() async {
    try {
      await _multicastChannel.invokeMethod('release');
    } on Object catch (error) {
      AppLogger.warning(
        'UdpDiscoveryTransport',
        'failed to release multicast lock',
        error,
      );
    }
  }

  @override
  void useKnownHosts(Iterable<String> hosts) {
    var added = 0;
    for (final host in hosts) {
      final trimmed = host.trim();
      if (trimmed.isEmpty || _knownHosts.contains(trimmed)) {
        continue;
      }
      if (_knownHosts.length >= maxKnownHosts) {
        break;
      }
      _knownHosts.add(trimmed);
      added++;
    }
    if (added == 0) {
      return;
    }
    // 套接字已打开时也要立刻生效：不只是记录下来等下次 open()。
    final current = probeTargets;
    probeTargets = <String>[...current, ..._knownHosts.where((h) => !current.contains(h))];
    AppLogger.info(
      'UdpDiscoveryTransport',
      'added $added known server host(s) as unicast probe targets: '
          '${_knownHosts.join(', ')}',
    );
  }

  @override
  Future<void> sendProbe(List<int> payload) async {
    final socket = _socket;
    if (socket == null) {
      throw const NetworkError('Discovery socket is not open');
    }
    for (final target in probeTargets) {
      try {
        socket.send(payload, InternetAddress(target), _probePort);
      } on Object catch (error) {
        // 单个目标发送失败不影响其他目标（例如无 IPv4 网卡时不支持广播）。
        AppLogger.debug(
          'UdpDiscoveryTransport',
          'probe to $target failed: ${AppLogger.sanitize('$error')}',
        );
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _socket?.close();
    _socket = null;
    if (Platform.isAndroid) {
      await _releaseMulticastLock();
    }
    await _controller.close();
  }

  /// 由 IPv4 地址与常见 /24 掩码推导定向广播地址。
  static String? _subnetBroadcastAddress(String ipv4) {
    final parts = ipv4.split('.');
    if (parts.length != 4) {
      return null;
    }
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) {
        return null;
      }
      octets.add(value);
    }
    return '${octets[0]}.${octets[1]}.${octets[2]}.255';
  }
}
