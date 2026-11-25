import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import 'app_colors.dart';
import 'dark_theme.dart';
import 'light_theme.dart';

export 'app_colors.dart';
export 'app_typography.dart';
export 'dark_theme.dart';

/// 应用主题入口（文档 #5.2）。
///
/// ```text
/// AppTheme
/// ├── light
/// ├── dark
/// ├── colors        (AppColors ThemeExtension)
/// ├── typography
/// ├── spacing / radius / motion / breakpoints
/// └── tdesign       (TDesign 主题数据)
/// ```
///
/// 业务页面禁止直接使用 `Color(0xFF...)`，统一通过
/// `Theme.of(context)` 或 `context.appColors` 取用设计变量。
abstract final class AppTheme {
  /// 浅色主题。
  static ThemeData light() => buildLightTheme();

  /// 深色主题。
  static ThemeData dark() => buildDarkTheme();

  /// 依据 [ThemeMode] 解析实际亮度。
  static Brightness resolveBrightness(ThemeMode mode, Brightness platform) {
    return switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platform,
    };
  }

  /// 解析当前应使用的 TDesign 主题数据。
  static TDThemeData tdesignData(ThemeMode mode, Brightness platform) {
    final base = TDTheme.defaultData();
    final brightness = resolveBrightness(mode, platform);
    if (brightness == Brightness.dark) {
      final dark = base.dark;
      if (dark != null) {
        return dark;
      }
    }
    return base.light;
  }

  /// 生成 TDesign 所需的系统 [ThemeData]。
  static ThemeData systemTheme(ThemeMode mode, Brightness platform) {
    final brightness = resolveBrightness(mode, platform);
    return brightness == Brightness.dark ? dark() : light();
  }
}

/// 便捷取色扩展。
extension AppColorsContext on BuildContext {
  /// 当前主题的设计变量。
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.of(this);
}
