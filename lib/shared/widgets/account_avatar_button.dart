import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../app/app_container.dart';
import '../../app/route_paths.dart';
import '../../core/constants/app_assets.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';

/// 右上角账号入口（文档 #9 / #41）。
///
/// 底部导航只保留四个内容入口（影视 / 人物 / 小说 / 漫画），
/// 管理模块改由每个页面右上角的头像进入：点击头像打开管理页，
/// 头像优先展示账号头像，没有头像时回落到品牌图标。
class AccountAvatarButton extends ConsumerWidget {
  /// 创建组件。
  const AccountAvatarButton({super.key, this.size = 30});

  /// 头像直径。
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final user = ref.watch(sessionManagerProvider).currentUser;
    final avatar = user?.avatarUrl;

    return Tooltip(
      message: context.l10n.managementTitle,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => context.push(RoutePaths.management),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.brandSubtle,
              border: Border.all(color: colors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: avatar == null
                ? _BrandFallback(size: size)
                : Image.network(
                    avatar.toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _BrandFallback(size: size),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 无账号头像时的品牌图标回退。
class _BrandFallback extends StatelessWidget {
  const _BrandFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    AppAssets.logo,
    width: size,
    height: size,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) =>
        Icon(TDIcons.user, size: size * 0.6, color: context.appColors.brand),
  );
}
