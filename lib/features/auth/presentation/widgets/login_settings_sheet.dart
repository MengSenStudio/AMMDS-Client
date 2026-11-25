import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../../../app/app_container.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_feedback.dart';

/// 打开登录页右上角的设置面板。
Future<void> showLoginSettingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const LoginSettingsSheet(),
    );

/// 登录页设置面板。
///
/// 内容是两组**刻意分开**的配置，避免用户把「应用配置」与「数据/隐私操作」
/// 混在一起（对应「这两类中间可以间隔开，避免混淆」的要求）：
///
/// ```text
/// 外观与应用   主题 / 语言 / 日志级别
/// ────────────────────────────────
/// 数据与隐私   清除缓存 / 版权与隐私
/// ```
class LoginSettingsSheet extends ConsumerStatefulWidget {
  /// 创建面板。
  const LoginSettingsSheet({super.key});

  @override
  ConsumerState<LoginSettingsSheet> createState() => _LoginSettingsSheetState();
}

class _LoginSettingsSheetState extends ConsumerState<LoginSettingsSheet> {
  /// 日志级别只保存在内存中，用它触发重建以反映最新选中态。
  LogLevel _logLevel = AppLogger.minimumLogLevel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.loginSettingsTitle,
              style: AppTypography.title.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.lg),
            _GroupLabel(text: l10n.settingsGroupApp),
            const SizedBox(height: AppSpacing.sm),
            _buildAppearanceChoices(context),
            const SizedBox(height: AppSpacing.xxl),
            // 两组之间留出明显间隔 + 分隔线，避免误认为是同一组配置
            Divider(color: colors.divider, height: 1),
            const SizedBox(height: AppSpacing.xxl),
            _GroupLabel(text: l10n.settingsGroupData),
            const SizedBox(height: AppSpacing.sm),
            _ActionRow(
              icon: TDIcons.cloud_download,
              label: l10n.clearCache,
              onTap: _clearCache,
            ),
            _ActionRow(
              icon: TDIcons.secured,
              label: l10n.copyrightPrivacy,
              onTap: _showCopyrightPrivacy,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceChoices(BuildContext context) {
    final l10n = context.l10n;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ChoiceRow(
          label: l10n.appTheme,
          options: <_Choice>[
            _Choice(
              l10n.themeFollowSystem,
              themeMode == ThemeMode.system,
              () =>
                  ref.read(themeModeProvider.notifier).update(ThemeMode.system),
            ),
            _Choice(
              l10n.themeLight,
              themeMode == ThemeMode.light,
              () =>
                  ref.read(themeModeProvider.notifier).update(ThemeMode.light),
            ),
            _Choice(
              l10n.themeDark,
              themeMode == ThemeMode.dark,
              () => ref.read(themeModeProvider.notifier).update(ThemeMode.dark),
            ),
          ],
        ),
        _ChoiceRow(
          label: l10n.appLanguage,
          options: <_Choice>[
            _Choice(
              l10n.themeFollowSystem,
              locale == null,
              () => ref.read(localeProvider.notifier).update(null),
            ),
            _Choice(
              l10n.languageChinese,
              locale?.languageCode == 'zh',
              () =>
                  ref.read(localeProvider.notifier).update(const Locale('zh')),
            ),
            _Choice(
              l10n.languageEnglish,
              locale?.languageCode == 'en',
              () =>
                  ref.read(localeProvider.notifier).update(const Locale('en')),
            ),
          ],
        ),
        _ChoiceRow(
          label: l10n.appLogLevel,
          options: <_Choice>[
            _Choice(
              l10n.logLevelDebug,
              _logLevel == LogLevel.debug,
              () => _setLogLevel(LogLevel.debug),
            ),
            _Choice(
              l10n.logLevelInfo,
              _logLevel == LogLevel.info,
              () => _setLogLevel(LogLevel.info),
            ),
            _Choice(
              l10n.logLevelWarning,
              _logLevel == LogLevel.warning,
              () => _setLogLevel(LogLevel.warning),
            ),
            _Choice(
              l10n.logLevelError,
              _logLevel == LogLevel.error,
              () => _setLogLevel(LogLevel.error),
            ),
          ],
        ),
      ],
    );
  }

  void _setLogLevel(LogLevel level) {
    AppLogger.minimumLogLevel = level;
    setState(() => _logLevel = level);
  }

  /// 清除缓存。
  ///
  /// 当前版本客户端没有离线内容库，因此这里清理的是图片与界面缓存；
  /// 不会触碰登录状态与服务器配置（对应提示文案中的承诺）。
  Future<void> _clearCache() async {
    final l10n = context.l10n;
    final confirmed = await AppDialog.confirm(
      context,
      title: l10n.clearCacheConfirmTitle,
      content: l10n.clearCacheConfirmMessage,
      confirmText: l10n.confirm,
      cancelText: l10n.cancel,
    );
    if (!confirmed || !mounted) {
      return;
    }
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    AppToast.success(context, l10n.clearCacheSuccess);
  }

  Future<void> _showCopyrightPrivacy() async {
    final l10n = context.l10n;
    await AppDialog.info(
      context,
      title: l10n.copyrightPrivacyTitle,
      content: l10n.copyrightPrivacyMessage,
      closeText: l10n.close,
    );
  }
}

/// 分组标题。
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Text(
      text,
      style: AppTypography.bodySmall.copyWith(color: colors.textTertiary),
    );
  }
}

/// 单个操作行。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(color: colors.textPrimary),
              ),
            ),
            Icon(TDIcons.chevron_right, size: 18, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 单选项。
class _Choice {
  const _Choice(this.label, this.selected, this.onSelect);

  final String label;
  final bool selected;
  final VoidCallback onSelect;
}

/// 一组互斥选项。
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.label, required this.options});

  final String label;
  final List<_Choice> options;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: options
                  .map(
                    (option) => InkWell(
                      onTap: option.onSelect,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: option.selected
                              ? colors.brandSubtle
                              : colors.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: option.selected
                                ? colors.brand
                                : colors.divider,
                          ),
                        ),
                        child: Text(
                          option.label,
                          style: AppTypography.caption.copyWith(
                            color: option.selected
                                ? colors.brand
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}
