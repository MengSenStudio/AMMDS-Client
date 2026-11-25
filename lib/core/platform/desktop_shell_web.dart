// 桌面外壳能力的 Web 实现。
//
// 浏览器既没有系统托盘与原生窗口（没有 `window_manager` / `tray_manager`
// 可用的运行时），也不允许写入登录项，因此这里全部退化为空操作，
// [DesktopShell.isSupported] 恒为 false，上层据此隐藏相关设置项。

import 'desktop_shell.dart';

/// 桌面外壳的 Web 空实现。
final class DesktopShellWeb implements DesktopShell {
  @override
  bool get isSupported => false;

  @override
  Future<void> initialize({
    required String appName,
    required TrayMenuLabels labels,
  }) async {}

  @override
  Future<bool> isAutoStartEnabled() async => false;

  @override
  Future<void> setAutoStart(bool enabled) async {}

  @override
  Future<void> dispose() async {}
}

/// 全局桌面外壳实例（Web 端为空实现，与 `main.dart` 的调用点保持一致）。
final DesktopShell desktopShell = DesktopShellWeb();
