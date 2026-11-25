import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// 项目自有设计变量的主题扩展（文档 #5.3 / #102）。
///
/// 业务 Widget 一律通过 `Theme.of(context).extension<AppColors>()`
/// 或 `context.appColors` 取色，禁止硬编码 `Color(0xFF...)`。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// 创建颜色集合。
  const AppColors({
    required this.brand,
    required this.brandHover,
    required this.brandActive,
    required this.brandSubtle,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.border,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.overlay,
    required this.shimmer,
  });

  /// 品牌主色。
  final Color brand;

  /// 品牌悬停色。
  final Color brandHover;

  /// 品牌按下色。
  final Color brandActive;

  /// 品牌浅色底（用于选中态背景）。
  final Color brandSubtle;

  /// 页面背景。
  final Color background;

  /// 卡片 / 容器表面。
  final Color surface;

  /// 次级表面（输入框、标签底色）。
  final Color surfaceVariant;

  /// 主文本。
  final Color textPrimary;

  /// 次文本。
  final Color textSecondary;

  /// 三级文本 / 占位符。
  final Color textTertiary;

  /// 分割线。
  final Color divider;

  /// 描边。
  final Color border;

  /// 成功。
  final Color success;

  /// 警告。
  final Color warning;

  /// 错误。
  final Color error;

  /// 信息。
  final Color info;

  /// 遮罩。
  final Color overlay;

  /// 骨架屏高亮。
  final Color shimmer;

  /// 浅色主题调色板。
  static const AppColors light = AppColors(
    brand: Color(0xFF0052D9),
    brandHover: Color(0xFF366EF4),
    brandActive: Color(0xFF003CAB),
    brandSubtle: Color(0xFFF2F3FF),
    background: Color(0xFFF3F3F3),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF5F5F5),
    textPrimary: Color(0xE6000000),
    textSecondary: Color(0x99000000),
    textTertiary: Color(0x66000000),
    divider: Color(0xFFE7E7E7),
    border: Color(0xFFDCDCDC),
    success: Color(0xFF2BA471),
    warning: Color(0xFFE37318),
    error: Color(0xFFD54941),
    info: Color(0xFF0052D9),
    overlay: Color(0x66000000),
    shimmer: Color(0xFFEEEEEE),
  );

  /// 深色主题调色板。
  static const AppColors dark = AppColors(
    brand: Color(0xFF366EF4),
    brandHover: Color(0xFF618DFF),
    brandActive: Color(0xFF003CAB),
    brandSubtle: Color(0xFF1B2A4A),
    background: Color(0xFF181818),
    surface: Color(0xFF242424),
    surfaceVariant: Color(0xFF2C2C2C),
    textPrimary: Color(0xE6FFFFFF),
    textSecondary: Color(0x99FFFFFF),
    textTertiary: Color(0x66FFFFFF),
    divider: Color(0xFF383838),
    border: Color(0xFF4B4B4B),
    success: Color(0xFF2BA471),
    warning: Color(0xFFFA9550),
    error: Color(0xFFF6685D),
    info: Color(0xFF618DFF),
    overlay: Color(0x99000000),
    shimmer: Color(0xFF2C2C2C),
  );

  /// 依据当前主题亮度返回调色板。
  static AppColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? dark : light;
  }

  @override
  AppColors copyWith({
    Color? brand,
    Color? brandHover,
    Color? brandActive,
    Color? brandSubtle,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? divider,
    Color? border,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? overlay,
    Color? shimmer,
  }) {
    return AppColors(
      brand: brand ?? this.brand,
      brandHover: brandHover ?? this.brandHover,
      brandActive: brandActive ?? this.brandActive,
      brandSubtle: brandSubtle ?? this.brandSubtle,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      divider: divider ?? this.divider,
      border: border ?? this.border,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      overlay: overlay ?? this.overlay,
      shimmer: shimmer ?? this.shimmer,
    );
  }

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }
    return AppColors(
      brand: Color.lerp(brand, other.brand, t)!,
      brandHover: Color.lerp(brandHover, other.brandHover, t)!,
      brandActive: Color.lerp(brandActive, other.brandActive, t)!,
      brandSubtle: Color.lerp(brandSubtle, other.brandSubtle, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      border: Color.lerp(border, other.border, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      shimmer: Color.lerp(shimmer, other.shimmer, t)!,
    );
  }
}

/// 间距令牌（文档 #102）。
abstract final class AppSpacing {
  /// 极小间距。
  static const double xxs = 2;

  /// 超小间距。
  static const double xs = 4;

  /// 小间距。
  static const double sm = 8;

  /// 中小间距。
  static const double md = 12;

  /// 标准间距。
  static const double lg = 16;

  /// 大间距。
  static const double xl = 24;

  /// 超大间距。
  static const double xxl = 32;

  /// 页面水平内边距。
  static const double page = 16;
}

/// 圆角令牌（文档 #102）。
abstract final class AppRadius {
  /// 小圆角。
  static const double sm = 2;

  /// 标准圆角。
  static const double md = 4;

  /// 大圆角。
  static const double lg = 8;

  /// 超大圆角。
  static const double xl = 12;

  /// 卡片圆角。
  static const double xxl = 20;

  /// 胶囊。
  static const double pill = 999;
}

/// 动效令牌（文档 #65）。
abstract final class AppMotion {
  /// 快速。
  static const Duration fast = Duration(milliseconds: 120);

  /// 标准。
  static const Duration normal = Duration(milliseconds: 220);

  /// 慢速。
  static const Duration slow = Duration(milliseconds: 360);

  /// 开屏动画时长。
  ///
  /// 官方开屏的最短展示时长：品牌动画是一条 3.6s 的缩放时间线
  /// （入场淡入 0.86→1.0 → 缓慢放大到 1.08 → 回落 1.0），
  /// 时长与开屏展示对齐，动画刚好收束时开屏关闭。
  static const Duration splash = Duration(milliseconds: 3600);

  /// 标准曲线。
  static const Curve standard = Curves.easeInOutCubic;

  /// 强调曲线。
  static const Curve emphasized = Curves.easeOutBack;
}

/// 响应式断点（文档 #101）。
abstract final class AppBreakpoints {
  /// 紧凑（手机）。
  static const double compact = 600;

  /// 中等（平板 / 窄窗口）。
  static const double medium = 1024;

  /// 展开（桌面）。
  static const double expanded = 1440;
}

/// 应用元信息。
abstract final class AppMeta {
  /// 版本号。
  static const String version = AppConstants.appVersion;
}
