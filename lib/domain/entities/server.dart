/// 服务端档案与连接状态领域模型（文档 #52 / #53）。
library;

/// 服务端连接状态（文档 #52）。
enum ServerConnectionState {
  /// 未连接。
  disconnected,

  /// 连接中。
  connecting,

  /// 已连接。
  connected,

  /// 服务端不可用。
  unavailable,

  /// 未授权。
  unauthorized,
}

/// 一个 AMMDS 服务端档案（文档 #53）。
///
/// 用户可以保存多个服务端并随时切换。
final class ServerProfile {
  /// 创建服务端档案。
  const ServerProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.protocol = 'http',
    this.apiVersion = 'v1',
    this.serverVersion,
    this.capabilities = const <String, bool>{},
    this.dialect,
    this.lastConnectedAt,
  });

  /// 唯一标识（发现协议中的 server_id，或手动配置时由地址派生）。
  final String id;

  /// 展示名称。
  final String name;

  /// 主机（IP 或域名）。
  final String host;

  /// 端口。
  final int port;

  /// 协议：`http` / `https`。
  final String protocol;

  /// API 版本，例如 `v1`。
  final String apiVersion;

  /// 服务端版本，例如 `1.0.0`。
  final String? serverVersion;

  /// 服务端能力（文档 #82）。
  final Map<String, bool> capabilities;

  /// 服务端接口方言（探测结果，见 ServerDialect）。
  final String? dialect;

  /// 最近一次连接成功时间。
  final DateTime? lastConnectedAt;

  /// 是否使用 HTTPS。
  bool get isHttps => protocol == 'https';

  /// 服务端根地址，例如 `http://192.168.1.100:8080`。
  Uri get baseUri => Uri(scheme: protocol, host: host, port: port, path: '/');

  /// 展示用地址。
  String get displayAddress => '$protocol://$host:$port';

  /// 是否为同一个服务端（按协议 + 主机 + 端口判定）。
  bool isSameEndpoint(ServerProfile other) =>
      protocol == other.protocol && host == other.host && port == other.port;

  /// 生成一个稳定的档案标识：优先使用服务端下发的 id，否则由端点派生。
  static String deriveId({
    required String protocol,
    required String host,
    required int port,
    String? serverId,
  }) {
    if (serverId != null && serverId.isNotEmpty) {
      return serverId;
    }
    return '$protocol://$host:$port';
  }

  /// 拷贝并覆盖部分字段。
  ServerProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? protocol,
    String? apiVersion,
    String? serverVersion,
    Map<String, bool>? capabilities,
    String? dialect,
    DateTime? lastConnectedAt,
  }) {
    return ServerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      protocol: protocol ?? this.protocol,
      apiVersion: apiVersion ?? this.apiVersion,
      serverVersion: serverVersion ?? this.serverVersion,
      capabilities: capabilities ?? this.capabilities,
      dialect: dialect ?? this.dialect,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  /// 序列化为可持久化的 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'protocol': protocol,
    'api_version': apiVersion,
    'server_version': serverVersion,
    'capabilities': capabilities,
    'dialect': dialect,
    'last_connected_at': lastConnectedAt?.toIso8601String(),
  };

  /// 从持久化 JSON 还原。
  static ServerProfile fromJson(
    Map<String, Object?> json, {
    String? fallbackId,
  }) {
    final host = json['host'] as String? ?? '';
    final port = (json['port'] as num?)?.toInt() ?? 0;
    final protocol = json['protocol'] as String? ?? 'http';
    final capabilities = <String, bool>{};
    final rawCapabilities = json['capabilities'];
    if (rawCapabilities is Map) {
      rawCapabilities.forEach((key, value) {
        if (value is bool) {
          capabilities['$key'] = value;
        }
      });
    }
    final lastConnectedAt = json['last_connected_at'] as String?;
    return ServerProfile(
      id:
          json['id'] as String? ??
          fallbackId ??
          deriveId(protocol: protocol, host: host, port: port),
      name: json['name'] as String? ?? host,
      host: host,
      port: port,
      protocol: protocol,
      apiVersion: json['api_version'] as String? ?? 'v1',
      serverVersion: json['server_version'] as String?,
      capabilities: capabilities,
      dialect: json['dialect'] as String?,
      lastConnectedAt: lastConnectedAt == null
          ? null
          : DateTime.tryParse(lastConnectedAt),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServerProfile &&
      other.id == id &&
      other.protocol == protocol &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(id, protocol, host, port);

  @override
  String toString() => 'ServerProfile($name @ $displayAddress)';
}

/// 用户手动录入的服务端地址解析结果（文档 #18）。
final class ServerAddressInput {
  const ServerAddressInput._({
    required this.protocol,
    required this.host,
    required this.port,
  });

  /// 协议。
  final String protocol;

  /// 主机。
  final String host;

  /// 端口。
  final int port;

  /// 解析用户输入的服务端地址。
  ///
  /// 支持：
  /// * `192.168.1.100`
  /// * `192.168.1.100:8080`
  /// * `http://192.168.1.100:8080`
  /// * `https://ammds.example.com`
  ///
  /// 解析失败返回 `null`，由调用方给出校验提示。
  static ServerAddressInput? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    var protocol = 'http';
    var rest = trimmed;
    final schemeMatch = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://')
        .firstMatch(trimmed);
    if (schemeMatch != null) {
      protocol = schemeMatch.group(1)!.toLowerCase();
      if (protocol != 'http' && protocol != 'https') {
        return null;
      }
      rest = trimmed.substring(schemeMatch.end);
    }
    // 去掉路径与查询串，仅保留 host[:port]
    rest = rest.split('/').first.split('?').first;
    if (rest.isEmpty) {
      return null;
    }

    var host = rest;
    var port = protocol == 'https' ? 443 : 80;
    final isIpv6Literal = rest.startsWith('[');
    if (isIpv6Literal) {
      final closing = rest.indexOf(']');
      if (closing < 0) {
        return null;
      }
      host = rest.substring(1, closing);
      final remainder = rest.substring(closing + 1);
      if (remainder.startsWith(':')) {
        final parsed = int.tryParse(remainder.substring(1));
        if (parsed == null) {
          return null;
        }
        port = parsed;
      }
    } else {
      final colon = rest.lastIndexOf(':');
      if (colon >= 0) {
        host = rest.substring(0, colon);
        final parsed = int.tryParse(rest.substring(colon + 1));
        if (parsed == null) {
          return null;
        }
        port = parsed;
      }
    }
    if (host.isEmpty || port <= 0 || port > 65535) {
      return null;
    }
    return ServerAddressInput._(protocol: protocol, host: host, port: port);
  }

  /// 组装 `host:port` 形式的展示文本。
  String get display => '$host:$port';

  /// 组装完整 URL。
  String get url {
    final defaultPort = protocol == 'https' ? 443 : 80;
    return port == defaultPort
        ? '$protocol://$host'
        : '$protocol://$host:$port';
  }
}
