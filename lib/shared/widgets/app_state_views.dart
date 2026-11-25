import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';

/// Loading 状态（文档 #47）。
class AppLoading extends StatelessWidget {
  /// 创建组件。
  const AppLoading({super.key, this.message});

  /// 附加文案。
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: TDLoading(
          size: TDLoadingSize.large,
          icon: TDLoadingIcon.circle,
          iconColor: context.appColors.brand,
          text: message ?? context.l10n.loading,
          textColor: context.appColors.textSecondary,
          axis: Axis.vertical,
        ),
      ),
    );
  }
}

/// Empty 状态（文档 #47）。
class AppEmpty extends StatelessWidget {
  /// 创建组件。
  const AppEmpty({
    super.key,
    this.message,
    this.operationText,
    this.onAction,
    this.icon,
  });

  /// 描述文案。
  final String? message;

  /// 操作按钮文案。
  final String? operationText;

  /// 操作回调。
  final VoidCallback? onAction;

  /// 图标。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final operation = operationText;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: TDEmpty(
          icon: icon ?? TDIcons.info_circle_filled,
          emptyText: message ?? context.l10n.emptyContent,
          emptyTextColor: context.appColors.textSecondary,
          type: operation == null ? TDEmptyType.plain : TDEmptyType.operation,
          operationText: operation,
          onTapEvent: onAction,
        ),
      ),
    );
  }
}

/// Error 状态（文档 #47）。
class AppErrorView extends StatelessWidget {
  /// 创建组件。
  const AppErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.retryText,
  });

  /// 错误文案（已本地化）。
  final String message;

  /// 重试回调。
  final VoidCallback? onRetry;

  /// 重试按钮文案。
  final String? retryText;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              TDIcons.error_circle_filled,
              size: 44,
              color: context.appColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              TDButton(
                text: retryText ?? context.l10n.retry,
                theme: TDButtonTheme.primary,
                size: TDButtonSize.medium,
                onTap: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 内容区状态包装：Loading / Error / Empty / Content（文档 #47 / #93）。
class AppStateView<T> extends StatelessWidget {
  /// 创建组件。
  const AppStateView({
    super.key,
    required this.isLoading,
    required this.isEmpty,
    required this.child,
    this.error,
    this.emptyMessage,
    this.onRetry,
    this.loadingMessage,
  });

  /// 是否加载中。
  final bool isLoading;

  /// 是否为空。
  final bool isEmpty;

  /// 错误文案（已本地化）。
  final String? error;

  /// 空状态文案。
  final String? emptyMessage;

  /// 重试回调。
  final VoidCallback? onRetry;

  /// 加载文案。
  final String? loadingMessage;

  /// 内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return AppLoading(message: loadingMessage);
    }
    final errorMessage = error;
    if (errorMessage != null) {
      return AppErrorView(message: errorMessage, onRetry: onRetry);
    }
    if (isEmpty) {
      return AppEmpty(message: emptyMessage);
    }
    return child;
  }
}
