/// 桌面外壳能力（托盘图标 / 关闭即最小化 / 开机自启）。
///
/// 这三项都属于**部分设备专属功能**：只有桌面平台（Windows / macOS / Linux）
/// 才有系统托盘与登录项，浏览器与移动端没有对应概念。因此这里只声明
/// 与平台无关的接口，具体实现按平台选择：
///
/// * IO 平台：`desktop_shell_io.dart`，由 `window_manager`（窗口）、
///   `tray_manager`（托盘）、`launch_at_startup`（开机自启）组合实现；
/// * Web：`desktop_shell_web.dart` 的空实现（`isSupported` 恒为 false）。
///
/// 上层（`main.dart` 与设置界面）只依赖本文件的接口：Web 与移动端构建
/// 不会引入桌面插件的 Dart 代码，也就不会被其中的 `dart:io` 污染。
library;

// IO 实现作为默认分支：静态分析（VM）与桌面 / 移动构建都走这一支；
// Web 构建时 `dart.library.js_interop` 为真，切换到空实现。
export 'desktop_shell_io.dart'
    if (dart.library.js_interop) 'desktop_shell_web.dart';

/// 托盘右键菜单的文案与目标地址。
///
/// 托盘菜单是**原生菜单**，在 `runApp` 之前创建，取不到 `BuildContext`，
/// 因此所有文案由调用方按系统语言解析后传入。
final class TrayMenuLabels {
  /// 创建菜单文案。
  const TrayMenuLabels({
    required this.showWindow,
    required this.autoStartEnable,
    required this.autoStartDisable,
    required this.website,
    required this.websiteUrl,
    required this.help,
    required this.helpUrl,
    required this.version,
    required this.exit,
  });

  /// 「主窗口」。
  final String showWindow;

  /// 「启用开机自启」（当前未开启时展示）。
  final String autoStartEnable;

  /// 「禁用开机自启」（当前已开启时展示）。
  final String autoStartDisable;

  /// 「官网」。
  final String website;

  /// 官网地址。
  final String websiteUrl;

  /// 「帮助」。
  final String help;

  /// 帮助地址。
  final String helpUrl;

  /// 版本号文案（已包含版本号本身，如「版本号 1.0.0」）。
  final String version;

  /// 「退出」。
  final String exit;
}

/// 桌面外壳能力抽象。
///
/// 非桌面平台上所有方法都是无害的空操作（见 `desktop_shell_web.dart`），
/// 调用方通过 [isSupported] 判断是否需要向用户暴露相关设置项。
abstract interface class DesktopShell {
  /// 当前平台的**原生外壳**是否可用（托盘图标 / 关闭即最小化 / 开机自启）。
  ///
  /// 仅桌面平台为 true；Web、Android、iOS 均为 false，此时
  /// [initialize] / [setAutoStart] 不做任何事。
  bool get isSupported;

  /// 初始化原生外壳：创建托盘图标、接管窗口关闭事件、准备开机自启。
  ///
  /// 必须在 `WidgetsFlutterBinding.ensureInitialized()` 之后调用。
  /// 初始化失败时抛出异常，由调用方决定是否降级（不得因此阻止应用启动）。
  ///
  /// [appName] 用于原生窗口标题与托盘提示；[labels] 为托盘右键菜单的文案，
  /// 菜单按用途分三组：
  ///
  /// ```text
  /// 主窗口 / 开机自启（启用 · 禁用）
  /// ────────────────────────────────
  /// 官网 / 帮助 / 版本号
  /// ────────────────────────────────
  /// 退出
  /// ```
  Future<void> initialize({
    required String appName,
    required TrayMenuLabels labels,
  });

  /// 当前是否已开启「开机自启」。
  ///
  /// 读取失败时返回 false（记录日志），不向用户抛出。
  Future<bool> isAutoStartEnabled();

  /// 写入「开机自启」开关。
  ///
  /// Windows 下写入注册表 `Run` 项；写入失败时抛出异常，
  /// 由调用方给出失败提示，而不是静默忽略。
  Future<void> setAutoStart(bool enabled);

  /// 释放托盘等原生资源。
  Future<void> dispose();
}
