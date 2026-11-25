import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/content.dart';

/// 统一图片加载组件（文档 #46）。
///
/// 统一处理 Loading / Error / Placeholder / 圆角 / 裁剪 / 比例，
/// 避免各页面自行实现。
///
/// 封面类图片的约定是「**固定容器 + 完整显示**」：容器尺寸由调用方给定
/// （[width] / [height]，或由父级固定），默认 [fit] 为 `contain`，
/// 因此不同比例的封面都不会被裁掉；容器底色使用次级表面色，
/// 让留白看起来是有意的画框而不是缺失。
class AppImage extends StatelessWidget {
  /// 创建组件。
  const AppImage({
    super.key,
    required this.uri,
    this.fallbackUri,
    this.width,
    this.height,
    this.radius = AppRadius.lg,
    this.fit = BoxFit.contain,
    this.placeholderIcon,
  });

  /// 图片地址。
  final Uri? uri;

  /// 回退地址：仅在 [uri] 加载失败时尝试一次。
  ///
  /// 远端封面一律经服务端代理下发，而服务端可能取不到图（图床在服务端所在网络被屏蔽、
  /// 手机却能访问）。此时直连原地址仍能显示，避免整页都是占位图。
  final Uri? fallbackUri;

  /// 宽度。
  final double? width;

  /// 高度。
  final double? height;

  /// 圆角。
  final double radius;

  /// 裁剪方式。
  final BoxFit fit;

  /// 占位图标。
  final IconData? placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final target = uri;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: target == null
            ? _placeholder(context)
            : ColoredBox(
                // 固定容器的底色：`contain` 留白处显示该底色，形成统一的画框
                color: context.appColors.surfaceVariant,
                child: _network(context, target, allowFallback: true),
              ),
      ),
    );
  }

  /// 构建网络图片；[allowFallback] 为真且加载失败时改用 [fallbackUri] 重试一次。
  ///
  /// 用「失败时直接返回另一个 Image」而不是维护内部状态：
  /// 回调本就是在构建期被调用，返回新组件即可原地替换，组件保持无状态、无副作用。
  Widget _network(BuildContext context, Uri target, {required bool allowFallback}) {
    final fallback = fallbackUri;
    return Image.network(
      target.toString(),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        if (allowFallback && fallback != null && fallback != target) {
          return _network(context, fallback, allowFallback: false);
        }
        return _placeholder(context);
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return _skeleton(context);
      },
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: context.appColors.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(
        placeholderIcon ?? Icons.image_outlined,
        color: context.appColors.textTertiary,
        size: 20,
      ),
    );
  }

  Widget _skeleton(BuildContext context) {
    return Container(
      color: context.appColors.shimmer,
      alignment: Alignment.center,
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          color: context.appColors.textTertiary,
        ),
      ),
    );
  }
}

/// 内容条目卡片（影视 / 人物 / 小说 / 漫画共用）。
///
/// 结构上把「标题区」固定高度、封面用剩余空间填充，
/// 因此无论网格分配的宽高比如何变化都不会出现纵向溢出。
///
/// 卡片自带可见边界（表面色 + 描边 + 圆角 + 内边距），
/// 而不是让封面直接贴在页面背景上，便于区分相邻条目。
class ContentCard extends StatelessWidget {
  /// 创建组件。
  const ContentCard({
    super.key,
    required this.item,
    this.onTap,
    this.aspectRatio = 2 / 3,
  });

  /// 内容条目。
  final ContentItem item;

  /// 点击回调。
  final VoidCallback? onTap;

  /// 封面比例（仅作为视觉参考，实际由网格分配）。
  final double aspectRatio;

  /// 标题区高度。
  static const double titleAreaHeight = 76;

  /// 卡片内边距。
  static const double cardPadding = AppSpacing.sm;

  /// 卡片描边宽度。
  static const double cardBorderWidth = 1;

  /// 卡片除封面与标题区之外占用的高度（内边距 + 上下描边）。
  ///
  /// 网格据此反推整卡高度，避免加入卡片边界后出现纵向溢出。
  static const double chromeHeight = cardPadding * 2 + cardBorderWidth * 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final rating = item.rating;
    final year = item.year;
    final subtitle = item.subtitle;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xxl),
      child: Container(
        padding: const EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: colors.border, width: cardBorderWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  AppImage(
                    uri: item.coverUri,
                    fallbackUri: item.coverFallbackUri,
                    radius: AppRadius.md,
                  ),
                  if (rating != null)
                    Positioned(
                      right: AppSpacing.xs,
                      top: AppSpacing.xs,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.overlay,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          rating.toStringAsFixed(1),
                          style: AppTypography.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: titleAreaHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxs,
                  AppSpacing.sm,
                  AppSpacing.xxs,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null || year != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          <String?>[
                            subtitle,
                            if (year != null) '$year',
                          ].whereType<String>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 内容网格（分页长列表，文档 #68）。
class ContentGrid extends StatelessWidget {
  /// 创建组件。
  const ContentGrid({
    super.key,
    required this.items,
    this.onItemTap,
    this.controller,
    this.aspectRatio = 2 / 3,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  /// 数据。
  final List<ContentItem> items;

  /// 点击回调。
  final void Function(ContentItem item)? onItemTap;

  /// 滚动控制器（用于分页触发）。
  final ScrollController? controller;

  /// 封面比例。
  final double aspectRatio;

  /// 内边距。

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    // 网格按「整卡高度 / 卡宽」设定 childAspectRatio：
    // 卡片高度 = 封面高度 + 标题区高度 + 卡片内边距与描边。
    // 这里显式按期望列宽反推，避免不同窗口宽度下出现纵向溢出。
    const maxExtent = 180.0;
    const spacing = AppSpacing.md;
    const columns = 160;
    final columnWidth = (columns - spacing) / (columns / maxExtent).ceil();
    final coverHeight = columnWidth / aspectRatio;
    final cardAspectRatio =
        columnWidth /
        (coverHeight + ContentCard.titleAreaHeight + ContentCard.chromeHeight);
    return GridView.builder(
      controller: controller,
      padding: padding,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: cardAspectRatio,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ContentCard(
          item: item,
          aspectRatio: aspectRatio,
          onTap: onItemTap == null ? null : () => onItemTap!(item),
        );
      },
    );
  }
}

/// 骨架屏列表。
class AppSkeletonList extends StatelessWidget {
  /// 创建组件。
  const AppSkeletonList({super.key, this.itemCount = 6});

  /// 条目数。
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: itemCount,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) => Container(
        height: 64,
        decoration: BoxDecoration(
          color: context.appColors.shimmer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }
}

/// 底部「没有更多了」提示。
class AppNoMoreFooter extends StatelessWidget {
  /// 创建组件。
  const AppNoMoreFooter({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
    child: Center(
      child: Text(
        context.l10n.noMore,
        style: AppTypography.caption.copyWith(
          color: context.appColors.textTertiary,
        ),
      ),
    ),
  );
}
