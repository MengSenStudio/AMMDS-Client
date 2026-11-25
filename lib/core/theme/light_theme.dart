import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'dark_theme.dart';

/// 浅色主题（文档 #5.1）。
///
/// 只允许在 [AppColors] 中定义具体颜色值。
ThemeData buildLightTheme() =>
    buildAppThemeData(brightness: Brightness.light, colors: AppColors.light);
