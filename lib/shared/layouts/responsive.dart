import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 响应式布局尺寸（文档 #36 / #101）。
enum AppWindowSize {
  /// 紧凑（手机）。
  compact,

  /// 中等（平板 / 窄窗口）。
  medium,

  /// 展开（桌面）。
  expanded;

  /// 是否为移动端形态（使用底部导航）。
  bool get isMobile => this == AppWindowSize.compact;

  /// 是否为桌面形态（使用侧边导航）。
  bool get isDesktop => this != AppWindowSize.compact;
}

/// 响应式布局工具。
abstract final class AppResponsive {
  /// 根据宽度解析尺寸。
  static AppWindowSize fromWidth(double width) {
    if (width < AppBreakpoints.compact) {
      return AppWindowSize.compact;
    }
    if (width < AppBreakpoints.medium) {
      return AppWindowSize.medium;
    }
    return AppWindowSize.expanded;
  }

  /// 从 [BuildContext] 解析当前尺寸。
  static AppWindowSize of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  /// 网格列数。
  static int gridColumns(AppWindowSize size) => switch (size) {
    AppWindowSize.compact => 3,
    AppWindowSize.medium => 4,
    AppWindowSize.expanded => 6,
  };
}

/// 依据窗口尺寸选择布局的构建器。
class ResponsiveBuilder extends StatelessWidget {
  /// 创建组件。
  const ResponsiveBuilder({super.key, required this.builder});

  /// 构建函数。
  final Widget Function(BuildContext context, AppWindowSize size) builder;

  @override
  Widget build(BuildContext context) =>
      builder(context, AppResponsive.of(context));
}
