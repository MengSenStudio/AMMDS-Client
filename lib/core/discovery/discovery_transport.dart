/// 发现传输层（文档 #16.1 / #17.1）。
///
/// 这里只定义**与平台无关**的抽象与数据类型；具体实现按平台选择：
///
/// * IO 平台（桌面 / 移动）：`discovery_transport_udp.dart` 的真实 UDP 实现；
/// * Web：`discovery_transport_web.dart` 的空实现（浏览器不支持 UDP）。
///
/// 上层 `DiscoveryService` 只依赖 [DiscoveryTransport]，因此协议逻辑可以在
/// 不依赖真实网络的情况下被完整测试（见 [FakeDiscoveryTransport]）。
library;

import 'dart:async';

import '../constants/discovery_constants.dart';
import '../errors/app_exception.dart';
import 'discovery_codec.dart';
import 'discovery_models.dart';

// UDP 实现作为默认分支：静态分析（VM）与桌面 / 移动构建都走这一支；
// Web 构建时 `dart.library.js_interop` 为真，切换到空实现。
export 'discovery_transport_udp.dart'
    if (dart.library.js_interop) 'discovery_transport_web.dart';

/// 一条原始发现报文。
final class DiscoveryDatagram {
  /// 创建报文。
  const DiscoveryDatagram({
    required this.bytes,
    required this.sourceAddress,
    required this.sourcePort,
  });

  /// 原始字节。
  final List<int> bytes;

  /// 来源地址。
  final String sourceAddress;

  /// 来源端口。
  final int sourcePort;
}

/// 发现传输抽象。
///
/// 上层 [DiscoveryService] 只依赖此接口，
/// 因此协议逻辑可以在不依赖真实网络的情况下被完整测试。
abstract interface class DiscoveryTransport {
  /// 打开套接字。
  ///
  /// [probePort] 为主动探测的目标端口（服务端监听端口）；
  /// [announcePort] 为本地绑定端口，用于接收服务端周期广播与探测应答。
  /// 绑定失败时实现应回退为系统分配的临时端口，并让 [receivesBroadcast]
  /// 返回 false——此时仍可通过「探测—应答」发现服务端。
  Future<void> open({int? probePort, int? announcePort});

  /// 发送一次探测请求。
  Future<void> sendProbe(List<int> payload);

  /// 接收到的报文流（探测应答 + 周期广播）。
  Stream<DiscoveryDatagram> get responses;

  /// 本机可用于探测的地址（含广播地址）。
  List<String> get probeTargets;

  /// 追加「已知服务端地址」作为**单播**探测目标。
  ///
  /// 存在的意义：广播在企业 Wi-Fi、Mesh、部分路由器策略下会被丢弃，
  /// 而单播往往仍然通。把用户已保存过的服务端地址直接点名探测，
  /// 这些网络里也能重新发现服务端，而不是只能手动输入。
  ///
  /// 允许在 [open] 之后调用（套接字已就绪时立即生效）。
  void useKnownHosts(Iterable<String> hosts);

  /// 实际绑定的本地端口。
  int get boundPort;

  /// 是否成功绑定了广播端口（可接收服务端主动广播）。
  bool get receivesBroadcast;

  /// 当前平台的发现传输是否**可用**。
  ///
  /// Web 端浏览器沙箱不允许收发 UDP，实现固定返回 false；上层据此给出明确提示，
  /// 而不是让用户面对一个「永远搜不到结果」的搜索状态。
  bool get isSupported;

  /// 关闭套接字并释放资源。
  Future<void> close();
}

/// 内存传输：用于单元测试与无网络环境下的确定性验证。
final class FakeDiscoveryTransport implements DiscoveryTransport {
  /// 创建内存传输。
  FakeDiscoveryTransport({
    this.replies = const <DiscoveryResponse>[],
    this.rawReplies = const <List<int>>[],
    this.throwOnSend = false,
    this.replyDelay = Duration.zero,
  });

  /// 用真实协议编码的响应。
  final List<DiscoveryResponse> replies;

  /// 直接注入的原始报文（用于构造非法响应）。
  final List<List<int>> rawReplies;

  /// 发送时是否抛出异常。
  final bool throwOnSend;

  /// 响应延迟。
  final Duration replyDelay;

  /// 报文流控制器（关闭后可重新创建，见 [open]）。
  StreamController<DiscoveryDatagram> _controller =
      StreamController<DiscoveryDatagram>.broadcast();

  /// 已发送的探测次数。
  int sendCount = 0;

  /// 是否已关闭。
  bool closed = false;

  @override
  List<String> probeTargets = const <String>['127.0.0.1'];

  @override
  int boundPort = 0;

  @override
  bool receivesBroadcast = true;

  @override
  bool get isSupported => true;

  /// 由 [useKnownHosts] 追加的单播目标（测试可断言）。
  final List<String> knownHosts = <String>[];

  @override
  void useKnownHosts(Iterable<String> hosts) {
    for (final host in hosts) {
      if (host.isEmpty || knownHosts.contains(host)) {
        continue;
      }
      knownHosts.add(host);
      probeTargets = <String>[...probeTargets, host];
    }
  }

  @override
  Stream<DiscoveryDatagram> get responses => _controller.stream;

  @override
  Future<void> open({int? probePort, int? announcePort}) async {
    closed = false;
    if (_controller.isClosed) {
      _controller = StreamController<DiscoveryDatagram>.broadcast();
    }
  }

  @override
  Future<void> sendProbe(List<int> payload) async {
    sendCount++;
    if (throwOnSend) {
      throw const NetworkError('fake transport send failure');
    }
    Future<void>.delayed(replyDelay, () {
      if (closed) {
        return;
      }
      for (final reply in replies) {
        _controller.add(
          DiscoveryDatagram(
            bytes: DiscoveryCodec.encodeResponse(reply),
            sourceAddress: reply.sourceAddress.isEmpty
                ? '127.0.0.1'
                : reply.sourceAddress,
            sourcePort: DiscoveryConstants.announcePort,
          ),
        );
      }
      for (final raw in rawReplies) {
        _controller.add(
          DiscoveryDatagram(
            bytes: raw,
            sourceAddress: '127.0.0.1',
            sourcePort: DiscoveryConstants.announcePort,
          ),
        );
      }
    });
  }

  @override
  Future<void> close() async {
    closed = true;
    await _controller.close();
  }
}
