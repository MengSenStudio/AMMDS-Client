import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/entities/server.dart';

/// 服务端选择卡片（文档 #57）。
///
/// 使用 TDesign 的 [TDCell]（单元格）承载条目、[TDTag] 承载能力标签，
/// 而不是手写 `InkWell` + `Container`：选中态、点击反馈、内边距、
/// 标题 / 描述排版都由组件库统一给出，避免自成一套的「野生」样式。
class ServerListTile extends StatelessWidget {
  /// 创建组件。
  const ServerListTile({
    super.key,
    required this.profile,
    required this.selected,
    this.onTap,
    this.onRemove,
    this.showCapabilities = true,
  });

  /// 服务端档案。
  final ServerProfile profile;

  /// 是否选中。
  final bool selected;

  /// 点击回调。
  final VoidCallback? onTap;

  /// 移除回调。
  final VoidCallback? onRemove;

  /// 是否展示能力标签。
  final bool showCapabilities;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TDCell(
      align: TDCellAlign.middle,
      leftIconWidget: Icon(
        TDIcons.server,
        size: 22,
        color: selected ? colors.brand : colors.textSecondary,
      ),
      title: profile.name,
      descriptionWidget: _buildDescription(context),
      rightIconWidget: _buildTrailing(context),
      onClick: onTap == null ? null : (_) => onTap!(),
      // TDCellStyle 的构造参数会被 `context` 触发的默认样式覆盖，
      // 因此先生成默认样式，再按选中态覆写需要变化的部分。
      style: TDCellStyle.cellStyle(context)
        ..backgroundColor = selected ? colors.brandSubtle : colors.surface
        ..clickBackgroundColor = colors.surfaceVariant
        ..titleStyle = AppTypography.subtitle.copyWith(color: colors.textPrimary)
        ..descriptionStyle = AppTypography.mono.copyWith(
          color: colors.textSecondary,
        )
        ..leftIconColor = selected ? colors.brand : colors.textSecondary
        ..rightIconColor = colors.textSecondary
        ..padding = const EdgeInsets.all(AppSpacing.md),
    );
  }

  /// 描述区：地址 + 能力标签。
  Widget _buildDescription(BuildContext context) {
    final colors = context.appColors;
    final capabilities = profile.capabilities.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          profile.displayAddress,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.mono.copyWith(color: colors.textSecondary),
        ),
        if (showCapabilities && capabilities.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: capabilities
                .map(
                  (capability) => TDTag(
                    _capabilityLabel(context, capability),
                    theme: TDTagTheme.primary,
                    size: TDTagSize.small,
                    isLight: true,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  /// 尾部区：移除按钮与选中标记。
  Widget? _buildTrailing(BuildContext context) {
    final colors = context.appColors;
    final hasAction = onRemove != null;
    if (!hasAction && !selected) {
      return null;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (hasAction)
          IconButton(
            onPressed: onRemove,
            tooltip: context.l10n.removeServer,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              TDIcons.delete,
              size: 18,
              color: colors.textTertiary,
            ),
          ),
        if (selected)
          Icon(TDIcons.check_circle_filled, color: colors.brand, size: 20),
      ],
    );
  }

  static String _capabilityLabel(BuildContext context, String capability) {
    final l10n = context.l10n;
    return switch (capability.toLowerCase()) {
      'media' => l10n.capabilityMedia,
      'people' => l10n.capabilityPeople,
      'novel' || 'novels' => l10n.capabilityNovel,
      'comic' || 'comics' => l10n.capabilityComic,
      _ => capability,
    };
  }
}
