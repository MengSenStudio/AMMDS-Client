import 'dart:io';

/// 平台相关的套接字错误信息提取（IO 实现）。
///
/// 单独成文件是为了让 Web 端也能编译：浏览器没有 `dart:io`，
/// 因此 Web 侧提供 [socket_failure_web.dart] 的空实现。

/// 取出 `SocketException` 的 OS 错误码；不是套接字错误时返回 `null`。
int? socketErrorCode(Object? error) =>
    error is SocketException ? error.osError?.errorCode : null;

/// 取出 `SocketException` 的原始文案（小写）；不是套接字错误时返回 `null`。
String? socketErrorMessage(Object? error) =>
    error is SocketException ? error.message.toLowerCase() : null;
