import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../../../app/app_container.dart';
import '../../../../app/route_paths.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/entities/content.dart';
import '../../../../domain/entities/server.dart';
import '../../../../shared/layouts/responsive.dart';
import '../../../../shared/widgets/account_avatar_button.dart';
import '../../../../shared/widgets/promote_dialog.dart';
import '../../../comic/presentation/pages/comic_page.dart';
import '../../../media/presentation/pages/media_page.dart';
import '../../../novel/presentation/pages/novel_page.dart';
import '../../../people/presentation/pages/people_page.dart';

/// 主界面导航项（文档 #34 / #99 / #100）。
///
/// 底部导航只保留四个**内容入口**：影视 / 人物 / 小说 / 漫画。
/// 管理（个人信息 / 服务器 / 应用配置 / 关于）不属于内容浏览，
/// 改由页面右上角的账号头像进入（见 `AccountAvatarButton`），
/// 避免底部导航项过多、挤压内容入口的可点击面积。
enum MainTab {
  /// 影视。
  media,

  /// 人物。
  people,

  /// 小说。
  novel,

  /// 漫画。
  comic;

  /// 路由路径。
  String get route => switch (this) {
    MainTab.media => RoutePaths.media,
    MainTab.people => RoutePaths.people,
    MainTab.novel => RoutePaths.novel,
    MainTab.comic => RoutePaths.comic,
  };

  /// 在导航中的序号。
  int get tabIndex => MainTab.values.indexOf(this);
}

/// 主界面宿主。
///
/// 由路由以 `MainShellHost(tab: ...)` 的形式渲染，
/// 内部使用 [IndexedStack] 在切换导航时保留页面状态（文档 #98）。
class MainShellHost extends StatelessWidget {
  /// 创建宿主。
  const MainShellHost({super.key, required this.tab});

  /// 当前 Tab。
  final MainTab tab;

  @override
  Widget build(BuildContext context) => MainShell(tab: tab);
}

/// 主界面（文档 #34 / #35 / #36）。
class MainShell extends ConsumerStatefulWidget {
  /// 创建页面。
  const MainShell({super.key, required this.tab});

  /// 当前 Tab。
  final MainTab tab;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late MainTab _tab = widget.tab;

  static const List<IconData> _icons = <IconData>[
    TDIcons.video,
    TDIcons.user,
    TDIcons.book,
    TDIcons.image,
  ];

  @override
  void initState() {
    super.initState();
    // 进入主界面即代表「已登录」：登录成功与启动时恢复会话最终都会走到这里，
    // 因此在首帧后统一检查一次官方推送（内部保证一次运行只检查一次）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(checkAndShowPromotesOnce(context, ref));
    });
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      _tab = widget.tab;
    }
  }

  /// 导航项文案，与 [MainTab] 顺序一一对应。
  List<String> _navLabels(BuildContext context) {
    final l10n = context.l10n;
    return <String>[
      l10n.navMedia,
      l10n.navPeople,
      l10n.navNovel,
      l10n.navComic,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, size) {
        final pages = <Widget>[
          const MediaPage(),
          const PeoplePage(),
          const NovelPage(),
          const ComicPage(),
        ];
        final visibleCount = MainTab.values.length;
        final index = _tab.tabIndex.clamp(0, visibleCount - 1);
        return Scaffold(
          body: size.isMobile
              ? SafeArea(
                  bottom: false,
                  child: IndexedStack(index: index, children: pages),
                )
              : Row(
                  children: <Widget>[
                    _buildNavigationRail(context, index, visibleCount),
                    const VerticalDivider(width: 0.5),
                    Expanded(
                      child: IndexedStack(index: index, children: pages),
                    ),
                  ],
                ),
          bottomNavigationBar: size.isMobile
              ? _buildBottomBar(context, index)
              : null,
        );
      },
    );
  }

  void _select(MainTab tab) {
    if (tab == _tab) {
      return;
    }
    setState(() => _tab = tab);
    context.go(tab.route);
  }

  Widget _buildNavigationRail(
    BuildContext context,
    int index,
    int visibleCount,
  ) {
    final l10n = context.l10n;
    final labels = _navLabels(context);
    final manager = ref.watch(serverManagerProvider);
    final colors = context.appColors;
    return NavigationRail(
      selectedIndex: index,
      onDestinationSelected: (value) => _select(MainTab.values[value]),
      labelType: NavigationRailLabelType.all,
      // 品牌图标替代原先写死的字母占位。
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Image.asset(AppAssets.logoHeader, fit: BoxFit.contain),
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 账号头像：进入管理模块（文档 #9）。
                const AccountAvatarButton(size: 32),
                const SizedBox(height: AppSpacing.sm),
                Tooltip(
                  message:
                      manager.activeServer?.displayAddress ??
                      l10n.noServerConfigured,
                  child: IconButton(
                    // 服务端发现页是子页面，必须 push，否则返回时无路可退。
                    onPressed: () => context.push(RoutePaths.deviceDiscovery),
                    icon: Icon(
                      manager.connectionState == ServerConnectionState.connected
                          ? TDIcons.check_circle
                          : TDIcons.server,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      destinations: <NavigationRailDestination>[
        for (var i = 0; i < visibleCount; i++)
          NavigationRailDestination(
            icon: Icon(_icons[i]),
            selectedIcon: Icon(_icons[i], color: colors.brand),
            label: Text(labels[i]),
          ),
      ],
    );
  }

  /// 移动端底部导航。
  ///
  /// 使用 TDesign 的 [TDBottomTabBar]，与页面内其它组件（`TDNavBar` / `TDButton` /
  /// `TDInput` …）保持同一套设计语言；只承载四个内容入口，
  /// 管理模块通过页面右上角头像进入（见 [AccountAvatarButton]）。
  Widget _buildBottomBar(BuildContext context, int index) {
    final labels = _navLabels(context);
    final colors = context.appColors;
    return TDBottomTabBar(
      TDBottomTabBarBasicType.iconText,
      navigationTabs: <TDBottomTabBarTabConfig>[
        for (var i = 0; i < labels.length; i++)
          TDBottomTabBarTabConfig(
            onTap: () => _select(MainTab.values[i]),
            selectedIcon: Icon(_icons[i], color: colors.brand, size: 22),
            unselectedIcon: Icon(
              _icons[i],
              color: colors.textSecondary,
              size: 22,
            ),
            tabText: labels[i],
            selectTabTextStyle: AppTypography.caption.copyWith(
              color: colors.brand,
            ),
            unselectTabTextStyle: AppTypography.caption.copyWith(
              color: colors.textSecondary,
            ),
            allowMultipleTaps: true,
          ),
      ],
      currentIndex: index,
      backgroundColor: colors.surface,
      selectedBgColor: colors.brandSubtle,
      unselectedBgColor: colors.surface,
    );
  }
}

/// 内容类型到路由路径的映射。
extension ContentKindRoute on ContentKind {
  /// 列表路由。
  String get listRoute => switch (this) {
    ContentKind.media => RoutePaths.media,
    ContentKind.people => RoutePaths.people,
    ContentKind.novel => RoutePaths.novel,
    ContentKind.comic => RoutePaths.comic,
  };

  /// 详情路由。
  String detailRoute(String id) => switch (this) {
    ContentKind.media => RoutePaths.mediaDetail(id),
    ContentKind.people => RoutePaths.peopleDetail(id),
    ContentKind.novel => RoutePaths.novelDetail(id),
    ContentKind.comic => RoutePaths.comicDetail(id),
  };
}
