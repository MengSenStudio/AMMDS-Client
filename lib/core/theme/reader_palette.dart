import 'package:flutter/material.dart';

import '../../domain/entities/reading.dart';

/// 阅读器配色（文档 #39 / #40 / #102）。
///
/// 阅读配色与 App 主题解耦：阅读是长时间沉浸场景，
/// 需要独立的浅色 / 米黄 / 夜间方案，而不是简单跟随系统主题。
/// 颜色集中在主题层定义，业务 Widget 只通过 [ReaderPalette.of] 取色。
@immutable
class ReaderPalette {
  /// 创建配色。
  const ReaderPalette({
    required this.background,
    required this.text,
    required this.secondary,
    required this.divider,
  });

  /// 页面背景。
  final Color background;

  /// 正文颜色。
  final Color text;

  /// 次要文字颜色。
  final Color secondary;

  /// 分割线颜色。
  final Color divider;

  /// 浅色。
  static const ReaderPalette light = ReaderPalette(
    background: Color(0xFFF7F7F8),
    text: Color(0xE6000000),
    secondary: Color(0x99000000),
    divider: Color(0xFFE3E3E5),
  );

  /// 护眼米黄。
  static const ReaderPalette sepia = ReaderPalette(
    background: Color(0xFFF2E7CE),
    text: Color(0xE63A2F1B),
    secondary: Color(0x993A2F1B),
    divider: Color(0xFFDCCDAC),
  );

  /// 护眼绿（长时间阅读更舒适）。
  static const ReaderPalette green = ReaderPalette(
    background: Color(0xFFCCE8CF),
    text: Color(0xE61F2D21),
    secondary: Color(0x991F2D21),
    divider: Color(0xFFB2D3B7),
  );

  /// 夜间。
  static const ReaderPalette dark = ReaderPalette(
    background: Color(0xFF15171A),
    text: Color(0xE6D8D8D8),
    secondary: Color(0x99D8D8D8),
    divider: Color(0xFF2A2D31),
  );

  /// 依据用户选择返回配色。
  static ReaderPalette of(ReaderBackground background) => switch (background) {
    ReaderBackground.light => light,
    ReaderBackground.sepia => sepia,
    ReaderBackground.green => green,
    ReaderBackground.dark => dark,
  };
}
