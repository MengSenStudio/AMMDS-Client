import '../constants/app_constants.dart';
import '../constants/discovery_constants.dart';

/// 发现协议请求（文档 #17）。
final class DiscoveryRequest {
  /// 创建请求。
  const DiscoveryRequest({
    this.protocol = DiscoveryConstants.protocol,
    this.version = DiscoveryConstants.version,
    this.service = DiscoveryConstants.service,
    this.clientId = 'ammds-client',
    this.clientVersion = AppConstants.appVersion,
  });

  /// 协议标识。
  final String protocol;

  /// 协议版本。
  final int version;

  /// 期望的服务类型。
  final String service;

  /// 客户端标识。
  final String clientId;

  /// 客户端版本。
  final String clientVersion;

  /// 请求类型，固定为 `discover`。
  String get type => 'discover';

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
    'protocol': protocol,
    'version': version,
    'service': service,
    'type': type,
    'client_id': clientId,
    'client_version': clientVersion,
  };
}

/// 发现协议响应（文档 #17 建议结构）。
final class DiscoveryResponse {
  /// 创建响应。
  const DiscoveryResponse({
    required this.protocol,
    required this.version,
    required this.service,
    required this.serverId,
    required this.name,
    required this.host,
    required this.port,
    this.apiVersion = 'v1',
    this.https = false,
    this.versionName,
    this.capabilities = const <String, bool>{},
    this.sourceAddress = '',
    this.sourceIsFallback = false,
    this.type = DiscoveryConstants.typeDiscoverResponse,
  });

  /// 协议标识。
  final String protocol;

  /// 协议版本。
  final int version;

  /// 服务类型。
  final String service;

  /// 服务端唯一标识。
  final String serverId;

  /// 服务端名称。
  final String name;

  /// 服务端地址（响应中的 host，缺失时回退为报文的来源地址）。
  final String host;

  /// 服务端端口。
  final int port;

  /// API 版本。
  final String apiVersion;

  /// 是否启用 HTTPS。
  final bool https;

  /// 服务端版本名。
  final String? versionName;

  /// 服务端能力（文档 #82）。
  final Map<String, bool> capabilities;

  /// 报文来源地址，用于去重与回退。
  final String sourceAddress;

  /// host 是否来自报文来源地址（响应未携带 host）。
  final bool sourceIsFallback;

  /// 报文类型：`discover_response`（探测应答）或 `announce`（服务端周期广播）。
  final String type;

  /// 是否为服务端主动广播（被动发现）。
  bool get isAnnounce => type == DiscoveryConstants.typeAnnounce;

  /// 协议名（http / https）。
  String get protocolName => https ? 'https' : 'http';

  /// 展示地址。
  String get displayAddress => '$protocolName://$host:$port';

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
    'protocol': protocol,
    'version': version,
    'service': service,
    'type': type,
    'server_id': serverId,
    'name': name,
    'host': host,
    'port': port,
    'api_version': apiVersion,
    'https': https,
    'version_name': versionName,
    'capabilities': capabilities,
  };

  /// 生成稳定的服务端标识。
  static String deriveServerId({
    required String host,
    required int port,
    String? serverId,
  }) {
    if (serverId != null && serverId.isNotEmpty) {
      return serverId;
    }
    return '$host:$port';
  }

  /// 去重键：同一服务端在多网卡下可能响应多次。
  String get dedupeKey => serverId;

  @override
  bool operator ==(Object other) =>
      other is DiscoveryResponse && other.serverId == serverId;

  @override
  int get hashCode => serverId.hashCode;

  @override
  String toString() => 'DiscoveryResponse($name, $displayAddress)';
}

/// 一次发现过程的结果。
final class DiscoveryOutcome {
  /// 创建结果。
  const DiscoveryOutcome({
    required this.servers,
    required this.invalidResponses,
    required this.rounds,
    required this.timedOut,
    this.error,
  });

  /// 去重后的服务端列表。
  final List<DiscoveryResponse> servers;

  /// 被忽略的非法响应数量。
  final int invalidResponses;

  /// 实际执行的探测轮次。
  final int rounds;

  /// 是否因超时结束。
  final bool timedOut;

  /// 底层错误（例如网卡不可用）。
  final Object? error;

  /// 是否发现服务端。
  bool get isEmpty => servers.isEmpty;
}
