// 平台相关的套接字错误信息提取（Web 实现）。
//
// 浏览器环境没有 `dart:io` / `SocketException`，网络失败只能依据
// 错误文案关键词归类，因此这里统一返回 null。

/// Web 端无法读取 OS 错误码。
int? socketErrorCode(Object? error) => null;

/// Web 端无法读取套接字原始文案。
String? socketErrorMessage(Object? error) => null;
