import '../../domain/entities/server.dart';

/// 服务端接口方言。
///
/// 服务端可能只实现文档约定的 Client API，也可能只提供既有的公开接口。
/// 方言在连接测试阶段探测一次并记录到 [ServerProfile.dialect]，
/// 之后所有请求都走同一条路径，避免每次请求重复探测。
enum ServerDialect {
  /// 文档约定的客户端专用接口：`/api/client/v1/**`。
  clientV1('client-v1'),

  /// 服务端既有的公开接口：`/api/oauth/**` + `/api/pub/**`。
  ammdsPublic('ammds-public');

  const ServerDialect(this.code);

  /// 持久化到服务端档案中的取值。
  final String code;

  /// 由持久化取值解析方言。
  static ServerDialect? parse(String? code) {
    if (code == null || code.isEmpty) {
      return null;
    }
    for (final dialect in ServerDialect.values) {
      if (dialect.code == code || dialect.name == code) {
        return dialect;
      }
    }
    return null;
  }

  /// 从服务端档案解析方言，未探测过时按 Client API 处理。
  static ServerDialect fromProfile(ServerProfile profile) =>
      parse(profile.dialect) ?? ServerDialect.clientV1;
}
