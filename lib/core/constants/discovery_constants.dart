/// 服务发现协议常量与 UDP 承载参数（文档 #16 / #17 / #109）。
///
/// 该模块是客户端**唯一**需要与服务端约定后可用的网络协议，
/// 协议字段与端口在此集中定义，避免散落在业务代码中。
library;

/// 发现协议常量。
abstract final class DiscoveryConstants {
  /// 请求 / 响应标识。
  static const String protocol = 'ammds-discovery';

  /// 协议版本。
  static const int version = 1;

  /// 服务类型标识。
  static const String service = 'ammds';

  /// 默认 UDP 发现端口（客户端主动探测的目标端口）。
  static const int port = 47823;

  /// 周期广播端口（服务端主动广播、客户端长期绑定接收）。
  ///
  /// 刻意与 [port] 分离：客户端需要长期绑定一个端口才能被动接收广播，
  /// 若两者相同，客户端与服务端部署在同一台机器时会抢占同一个 UDP 端口。
  static const int announcePort = 47824;

  /// 探测应答报文类型。
  static const String typeDiscoverResponse = 'discover_response';

  /// 周期广播报文类型（服务端主动广播，无需客户端探测）。
  static const String typeAnnounce = 'announce';

  /// 持续发现模式下的重新探测间隔。
  ///
  /// 服务端默认每 15 秒广播一次，客户端以更短的间隔主动补探测，
  /// 保证「App 刚打开」与「服务端刚启动」两种时机都能被发现（文档 #17.2）。
  static const Duration watchProbeInterval = Duration(seconds: 5);

  /// 广播地址（IPv4 受限广播）。
  static const String broadcastAddress = '255.255.255.255';

  /// IPv4 多播地址。
  static const String multicastAddressV4 = '239.255.42.99';

  /// IPv6 多播地址。
  static const String multicastAddressV6 = 'ff02::1';

  /// 单次探测的超时时间。
  static const Duration probeTimeout = Duration(milliseconds: 700);

  /// 探测轮次（短时间多次探测，而非一次长时间阻塞）。
  static const int probeRounds = 4;

  /// 每轮探测之间的延迟。
  static const Duration probeInterval = Duration(milliseconds: 350);

  /// 单个 UDP 报文最大长度，超出视为非法响应。
  static const int maxDatagramSize = 4096;

  /// 本机探测地址，保证 `localhost` 场景下也能发现服务端。
  static const String loopbackProbeAddress = '127.0.0.1';
}

/// 发现相关的错误码。
abstract final class DiscoveryErrorCodes {
  /// 协议字段缺失或非法。
  static const String malformed = 'malformed_response';

  /// 协议标识不匹配。
  static const String protocolMismatch = 'protocol_mismatch';

  /// 协议版本不兼容。
  static const String versionIncompatible = 'version_incompatible';

  /// 服务类型不匹配。
  static const String serviceMismatch = 'service_mismatch';

  /// 响应超长。
  static const String tooLarge = 'response_too_large';
}
