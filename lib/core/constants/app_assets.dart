/// 静态资源清单。
///
/// 这里的资源直接取自 `app/`（AMMDS 前端工程）中的品牌资源，
/// 保证客户端与服务端前端使用同一套视觉资产。
///
/// 三个品牌图的用途刻意区分，避免混用：
///
/// | 资源 | 形态 | 使用位置 |
/// | --- | --- | --- |
/// | [logo] | 1024×1024、自带白色背景的方形应用图标 | 应用图标、头像等需要「实底方块」的位置 |
/// | [logoHeader] | 无背景、无文字的透明图标 | 开屏品牌区、导航栏、关于页 |
/// | [loginBanner] | 无背景、图标 + AMMDS 文字的上下结构 | 登录页顶部品牌区 |
abstract final class AppAssets {
  /// 应用图标（方形、自带背景）。
  ///
  /// 同时作为各平台原生图标的生成源（Windows `.ico`、Android `mipmap`、
  /// iOS/macOS `AppIcon`、Web `icons/`）。
  static const String logo = 'assets/images/ammds-logo.png';

  /// 透明背景的品牌图标（无文字），用于开屏与导航等需要与背景融合的位置。
  static const String logoHeader = 'assets/images/logo_header.png';

  /// 登录页品牌图（透明背景，图标 + AMMDS 文字）。
  static const String loginBanner = 'assets/images/login-banner.png';

  /// 桌面托盘图标（Windows 使用）。
  ///
  /// Windows 的系统托盘只接受 `.ico`，因此这里单独提供一份；macOS / Linux
  /// 直接使用 [logoHeader] 的透明 PNG（见 `desktop_shell_io.dart`）。
  ///
  /// 各帧是**未压缩的 DIB 位图**而非 PNG 压缩帧：后者在部分托盘实现里
  /// 无法解码，会显示成空白图标。
  static const String appIcon = 'assets/icons/logo.ico';
}
