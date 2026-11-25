/// 平台相关的套接字错误信息提取。
///
/// `dart:io` 只在 IO 平台可用，Web 端由 Web 实现提供空结果，
/// 使错误归类逻辑本身不依赖具体平台。
library;

// IO 实现作为默认分支：静态分析（VM）与桌面 / 移动构建都走这一支；
// Web 构建时 `dart.library.js_interop` 为真，切换到空实现。
export 'socket_failure_io.dart'
    if (dart.library.js_interop) 'socket_failure_web.dart';
