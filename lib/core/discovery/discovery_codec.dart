import 'dart:convert';

import '../constants/discovery_constants.dart';
import 'discovery_models.dart';

/// 发现协议的编解码实现（文档 #17）。
///
/// * [encodeRequest]：把 [DiscoveryRequest] 编码为 UDP 报文。
/// * [decodeResponse]：解析服务端响应；非法响应抛出
///   [DiscoveryProtocolException]，由调用方忽略（不影响其他服务端）。
abstract final class DiscoveryCodec {
  /// 编码探测请求。
  static List<int> encodeRequest(DiscoveryRequest request) =>
      utf8.encode(jsonEncode(request.toJson()));

  /// 编码响应（服务端 / 测试桩使用）。
  static List<int> encodeResponse(DiscoveryResponse response) =>
      utf8.encode(jsonEncode(response.toJson()));

  /// 解析服务端响应。
  ///
  /// 抛出 [DiscoveryProtocolException] 的场景：
  /// 报文非法 JSON、超长、协议标识不匹配、服务类型不匹配、版本不兼容、
  /// 必要字段缺失。
  static DiscoveryResponse decodeResponse(
    List<int> datagram, {
    required String sourceAddress,
  }) {
    if (datagram.length > DiscoveryConstants.maxDatagramSize) {
      throw DiscoveryProtocolException(
        DiscoveryErrorCodes.tooLarge,
        'Datagram exceeds ${DiscoveryConstants.maxDatagramSize} bytes',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(datagram, allowMalformed: false));
    } on FormatException catch (error) {
      throw DiscoveryProtocolException(
        DiscoveryErrorCodes.malformed,
        'Response is not valid JSON',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const DiscoveryProtocolException(
        DiscoveryErrorCodes.malformed,
        'Response root must be a JSON object',
      );
    }

    final protocol = _stringValue(decoded['protocol']);
    if (protocol != DiscoveryConstants.protocol) {
      throw DiscoveryProtocolException(
        DiscoveryErrorCodes.protocolMismatch,
        'Unexpected protocol: $protocol',
      );
    }
    final service = _stringValue(decoded['service']);
    if (service != DiscoveryConstants.service) {
      throw DiscoveryProtocolException(
        DiscoveryErrorCodes.serviceMismatch,
        'Unexpected service: $service',
      );
    }

    final version = _intValue(decoded['version']);
    if (version == null) {
      throw const DiscoveryProtocolException(
        DiscoveryErrorCodes.malformed,
        'Missing protocol version',
      );
    }
    if (version > DiscoveryConstants.version) {
      throw DiscoveryProtocolException(
        DiscoveryErrorCodes.versionIncompatible,
        'Unsupported protocol version: $version',
      );
    }

    final port = _intValue(decoded['port']);
    if (port == null || port <= 0 || port > 65535) {
      throw const DiscoveryProtocolException(
        DiscoveryErrorCodes.malformed,
        'Missing or invalid port',
      );
    }

    final rawHost = _stringValue(decoded['host']);
    final host = (rawHost == null || rawHost.isEmpty) ? sourceAddress : rawHost;

    final serverId = _stringValue(decoded['server_id']);
    final name = _stringValue(decoded['name']);
    final capabilities = <String, bool>{};
    final rawCapabilities = decoded['capabilities'];
    if (rawCapabilities is Map) {
      rawCapabilities.forEach((key, value) {
        if (value is bool) {
          capabilities['$key'] = value;
        }
      });
    }

    return DiscoveryResponse(
      protocol: protocol!,
      version: version,
      service: service!,
      serverId: DiscoveryResponse.deriveServerId(
        serverId: serverId,
        host: host,
        port: port,
      ),
      name: (name == null || name.isEmpty) ? 'AMMDS Server' : name,
      host: host,
      port: port,
      apiVersion: _stringValue(decoded['api_version']) ?? 'v1',
      https: _boolValue(decoded['https']) ?? false,
      versionName: _stringValue(decoded['version_name']),
      capabilities: capabilities,
      sourceAddress: sourceAddress,
      sourceIsFallback: rawHost == null || rawHost.isEmpty,
      // 兼容尚未实现周期广播的服务端：缺失 type 时按探测应答处理
      type:
          _stringValue(decoded['type']) ??
          DiscoveryConstants.typeDiscoverResponse,
    );
  }

  static String? _stringValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    return '$value';
  }

  static int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static bool? _boolValue(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      if (value.toLowerCase() == 'true') {
        return true;
      }
      if (value.toLowerCase() == 'false') {
        return false;
      }
    }
    return null;
  }
}

/// 发现协议错误。
final class DiscoveryProtocolException implements Exception {
  /// 创建错误。
  const DiscoveryProtocolException(this.code, this.message, {this.cause});

  /// 错误码，见 [DiscoveryErrorCodes]。
  final String code;

  /// 描述。
  final String message;

  /// 原始原因。
  final Object? cause;

  @override
  String toString() => 'DiscoveryProtocolException($code): $message';
}
