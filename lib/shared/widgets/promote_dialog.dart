import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_container.dart';
import '../../core/l10n/l10n.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/promote.dart';

/// 单次运行内是否已经检查过官方推送。
///
/// 主界面在切换 Tab 时会重新构建宿主，若不加这个开关，每次切换都会重新
/// 拉取一次通告。这里用「进程内一次性」语义：一次启动只检查一次。
bool _promoteChecked = false;

/// 进入主界面后检查并展示官方推送通告（一次运行只检查一次）。
///
/// 对应网页端在导航栏挂载后、确认登录态有效时展示「官方推送」的行为：
/// 登录成功与「启动时本地会话仍有效」最终都会进入主界面，因此一个入口
/// 覆盖两种情况。
///
/// @return 本次实际展示的条数，0 表示没有需要提醒的通告
Future<int> checkAndShowPromotesOnce(BuildContext context, WidgetRef ref) async {
  if (_promoteChecked) {
    return 0;
  }
  _promoteChecked = true;
  return showPendingPromotes(context, ref);
}

/// 拉取并依次展示「处于推送窗口内且当日未读」的官方推送。
///
/// 与网页端一致：一次只展示一条，用户点击「已读」或「前往」后再展示下一条。
///
/// @return 本次实际展示的条数
Future<int> showPendingPromotes(BuildContext context, WidgetRef ref) async {
  final repository = ref.read(promoteRepositoryProvider);
  final pending = await repository.pending();
  if (pending.isEmpty || !context.mounted) {
    return 0;
  }
  var shown = 0;
  for (final promote in pending) {
    if (!context.mounted) {
      break;
    }
    await showPromoteDialog(context, promote);
    // 展示过即记为「当日已读」：这是网页端的语义，也是避免反复打扰的关键
    await repository.markRead(promote.id);
    shown++;
  }
  return shown;
}

/// 展示单条官方推送（遮罩与 ESC 均不可关闭，必须显式选择「已读 / 前往」）。
Future<void> showPromoteDialog(BuildContext context, AppPromote promote) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PromoteDialog(promote: promote),
    );

/// 官方推送弹窗。
class PromoteDialog extends StatelessWidget {
  /// 创建弹窗。
  const PromoteDialog({super.key, required this.promote});

  /// 通告内容。
  final AppPromote promote;

  Future<void> _openWebsite(BuildContext context) async {
    final website = promote.website;
    if (website == null) {
      return;
    }
    // 先尝试打开链接再关闭弹窗：保持「用户手势内发起」，
    // 否则浏览器会把新窗口当成弹窗拦截掉。
    try {
      await launchUrl(website);
    } on Object catch (error) {
      AppLogger.warning('PromoteDialog', 'open promote website failed', error);
    }
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final banner = promote.banner;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text(
                promote.dialogTitle?.isNotEmpty == true
                    ? promote.dialogTitle!
                    : l10n.promoteDialogTitle,
                style: AppTypography.title.copyWith(color: colors.textPrimary),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (banner != null) _PromoteBanner(uri: banner),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.xl,
                        AppSpacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            promote.title,
                            style: AppTypography.subtitle.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          if (promote.description != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              promote.description!,
                              style: AppTypography.bodySmall.copyWith(
                                color: colors.textSecondary,
                                height: 1.6,
                              ),
                            ),
                          ],
                          if (promote.tip != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              promote.tip!,
                              style: AppTypography.caption.copyWith(
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(color: colors.divider, height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  TDButton(
                    text: l10n.promoteRead,
                    type: TDButtonType.outline,
                    size: TDButtonSize.medium,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  if (promote.website != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.md),
                    TDButton(
                      text: promote.buttonText?.isNotEmpty == true
                          ? promote.buttonText!
                          : l10n.promoteGo,
                      theme: TDButtonTheme.primary,
                      size: TDButtonSize.medium,
                      onTap: () => _openWebsite(context),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 通告配图。
///
/// 两个必须守住的点（对应「图片被压成正方形 / 变形」的反馈）：
///
/// * **保持原始比例**：`BoxFit.contain` + 只给最大高度，不写死高度、不用 `cover`。
///   写死高度再 `cover` 会把任意比例的图裁成同一个框，竖图（例如二维码）必然变形；
/// * **加载失败要给出明确占位**：官方图床对部分内容（含二维码等）会拒绝下发，
///   此时展示一行「配图无法加载」而不是空白方块或破图，也不影响正文与按钮。
class _PromoteBanner extends StatelessWidget {
  const _PromoteBanner({required this.uri});

  /// 图片地址。
  final Uri uri;

  /// 配图最大高度；超出的图按比例缩放，不裁切。
  static const double maxHeight = 260;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: maxHeight),
      child: Image.network(
        uri.toString(),
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          AppLogger.warning(
            'PromoteDialog',
            'banner load failed: ${AppLogger.sanitize(uri.toString())}',
            error,
          );
          return _buildFallback(context);
        },
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 88,
      color: colors.surfaceVariant,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(TDIcons.error_circle, size: 20, color: colors.textTertiary),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.promoteBannerFailed,
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
