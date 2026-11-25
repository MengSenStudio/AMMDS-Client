import 'package:flutter/material.dart';

/// 字体令牌（文档 #102）。
///
/// 仅定义字号 / 字重 / 行高，颜色由 [AppColors] 决定，
/// 因此同一份排版令牌可同时服务浅色与深色主题。
abstract final class AppTypography {
  /// 超大标题（开屏品牌名）。
  static const TextStyle display = TextStyle(
    fontSize: 34,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
  );

  /// 页面大标题。
  static const TextStyle headline = TextStyle(
    fontSize: 24,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  /// 区块标题。
  static const TextStyle title = TextStyle(
    fontSize: 18,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  /// 卡片标题。
  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );

  /// 正文。
  static const TextStyle body = TextStyle(fontSize: 14, height: 1.5);

  /// 次要正文。
  static const TextStyle bodySmall = TextStyle(fontSize: 13, height: 1.45);

  /// 说明文字。
  static const TextStyle caption = TextStyle(fontSize: 12, height: 1.4);

  /// 按钮文字。
  static const TextStyle button = TextStyle(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w500,
  );

  /// 等宽（地址、版本号）。
  static const TextStyle mono = TextStyle(
    fontSize: 13,
    height: 1.4,
    fontFamily: 'monospace',
  );
}
