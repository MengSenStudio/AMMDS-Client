/// 存储装配（文档 #24 / #43 / #44 / #51.2）。
///
/// 接口在 `storage.dart`，实现按平台选择：
///
/// * **IO 平台（桌面 / 移动）**：文件型实现（`storage_impl_file.dart`），
///   同时导出内存实现供测试与降级使用；
/// * **Web**：内存实现（浏览器没有 `dart:io`，也不引入额外的存储依赖）。
///
/// 装配层（`main.dart`）只调用 [createPreferencesStorage] /
/// [createSecureStorage]，因此业务代码完全不感知平台差异。
library;

// IO 实现作为默认分支：静态分析（VM）与桌面 / 移动构建都走这一支；
// Web 构建时 `dart.library.js_interop` 为真，切换到内存实现。
export 'storage_factory_io.dart'
    if (dart.library.js_interop) 'storage_factory_web.dart';
