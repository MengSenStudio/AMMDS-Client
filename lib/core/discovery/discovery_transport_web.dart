import 'dart:async';

import 'discovery_transport.dart';

/// Web 端的发现传输占位实现。
///
/// 浏览器沙箱不允许主动发送 / 接收 UDP 报文，因此局域网自动发现在 Web 上不可用。
/// 本类保留与 IO 实现**完全一致的公开签名**，使上层（`DiscoveryService`、
/// 依赖容器）无需按平台分支；行为上：
///
/// * [open] 立即成功，但 [receivesBroadcast] 恒为 false；
/// * [probeTargets] 为空，[sendProbe] 不做任何事；
/// * [responses] 永远不产生报文，因此发现结果恒为空。
///
/// 结果是 Web 端「发现内网服务器」列表为空，用户改用登录页手填服务端地址。
final class UdpDiscoveryTransport implements DiscoveryTransport {
  /// 创建占位传输（参数与 IO 实现保持一致）。
  UdpDiscoveryTransport({
    this.additionalProbeTargets = const <String>[],
    this.enableBroadcast = true,
  });

  /// 额外探测目标（Web 端不使用）。
  final List<String> additionalProbeTargets;

  /// 是否使用受限广播地址（Web 端不使用）。
  final bool enableBroadcast;

  static final StreamController<DiscoveryDatagram> _controller =
      StreamController<DiscoveryDatagram>.broadcast();

  @override
  Stream<DiscoveryDatagram> get responses => _controller.stream;

  @override
  List<String> probeTargets = const <String>[];

  @override
  int boundPort = 0;

  @override
  bool receivesBroadcast = false;

  /// 浏览器沙箱不支持 UDP，发现能力不可用。
  @override
  bool get isSupported => false;

  @override
  Future<void> open({int? probePort, int? announcePort}) async {}

  /// Web 端不支持 UDP，记录已知主机也没有意义。
  @override
  void useKnownHosts(Iterable<String> hosts) {}

  @override
  Future<void> sendProbe(List<int> payload) async {}

  @override
  Future<void> close() async {}
}
