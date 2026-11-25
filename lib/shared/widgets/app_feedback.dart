import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 统一的 TDesign 提示封装。
///
/// 业务页面不直接调用 `TDToast`，便于后续统一替换提示样式。
abstract final class AppToast {
  /// 成功提示。
  static void success(BuildContext context, String message) {
    TDToast.showSuccess(message, context: context);
  }

  /// 失败提示。
  static void failure(BuildContext context, String message) {
    TDToast.showFail(message, context: context);
  }

  /// 警告提示。
  static void warning(BuildContext context, String message) {
    TDToast.showWarning(message, context: context);
  }

  /// 文本提示。
  static void text(BuildContext context, String message) {
    TDToast.showText(message, context: context);
  }
}

/// 统一的确认 / 提示对话框（TDesign，自动适配浅色 / 深色）。
///
/// 业务页面不直接使用 `TDAlertDialog` / `TDConfirmDialog`，
/// 便于后续统一调整交互与文案。
abstract final class AppDialog {
  /// 展示确认对话框，返回用户是否确认。
  ///
  /// 两侧按钮都显式指定 `action` 并自行 `pop`，因为 TDesign 的按钮在
  /// 提供 `action` 时**不会**自动关闭弹窗（不提供时才默认 pop）。
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String content,
    String? confirmText,
    String? cancelText,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => TDAlertDialog(
        title: title,
        content: content,
        leftBtn: TDDialogButtonOptions(
          title: cancelText ?? 'Cancel',
          action: () => Navigator.of(dialogContext).pop(false),
        ),
        rightBtn: TDDialogButtonOptions(
          title: confirmText ?? 'OK',
          theme: TDButtonTheme.primary,
          action: () => Navigator.of(dialogContext).pop(true),
        ),
      ),
    );
    return confirmed ?? false;
  }

  /// 展示一个只有「知道了」的信息对话框。
  static Future<void> info(
    BuildContext context, {
    required String title,
    required String content,
    String? closeText,
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) => TDConfirmDialog(
      title: title,
      content: content,
      buttonText: closeText ?? 'OK',
      action: () => Navigator.of(dialogContext).pop(),
    ),
  );
}
