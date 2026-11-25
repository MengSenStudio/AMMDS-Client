import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/logging/app_logger.dart';
import '../core/theme/app_theme.dart';
import '../domain/entities/content.dart';
import '../domain/services/bootstrap_manager.dart';
import '../features/auth/presentation/pages/device_select_page.dart';
import '../features/auth/presentation/pages/login_page.dart';
import '../features/comic/presentation/pages/comic_page.dart';
import '../features/comic/presentation/pages/comic_reader_page.dart';
import '../features/home/presentation/pages/main_shell.dart';
import '../features/management/presentation/pages/management_page.dart';
import '../features/media/presentation/pages/media_page.dart';
import '../features/media/presentation/pages/media_player_page.dart';
import '../features/novel/presentation/pages/novel_page.dart';
import '../features/novel/presentation/pages/novel_reader_page.dart';
import '../features/people/presentation/pages/people_page.dart';
import '../features/splash/presentation/pages/splash_page.dart';
import 'app_container.dart';
import 'route_paths.dart';

/// 路由提供者（文档 #12 / #98）。
///
/// 路由守卫依据 [BootstrapManager] 的启动结果决定进入 `Main` 还是 `Login`，
/// 页面本身不判断登录状态；页面切换时通过 [MainShellHost] 保留各 Tab 状态。
///
/// 转场策略（对应「进入新页面时内容是中心放大的过渡，很丑」的反馈）：
///
/// * **顶级 Tab（影视 / 人物 / 小说 / 漫画）与开屏 / 登录页**：无转场动画。
///   Tab 之间没有层级关系，播放 Material 默认的「中心放大」动画既突兀，
///   也会让底部导航栏看起来消失后重建；
/// * **子页面（详情 / 阅读器 / 管理 / 服务端发现）**：从右侧滑入 + 淡入，
///   符合层级导航的通用预期。
final routerProvider = Provider<GoRouter>((ref) {
  final manager = ref.watch(bootstrapManagerProvider);
  final refresh = _RouterRefreshNotifier(manager);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: false,
    refreshListenable: refresh,
    redirect: (context, state) {
      final bootstrap = manager.state;
      final location = state.matchedLocation;
      // 启动未完成前一律停留在开屏页；启动完成后由 SplashPage 自行决定跳转，
      // 因为开屏需要保证最短展示时长，不能由路由在完成瞬间立即切走。
      if (!bootstrap.isCompleted) {
        return location == RoutePaths.splash ? null : RoutePaths.splash;
      }
      if (location == RoutePaths.splash) {
        return null;
      }
      final authenticated = ref.read(sessionManagerProvider).isAuthenticated();
      // 登录页与服务端选择页在未登录时也必须可达：
      // 「发现内网服务器」正是从登录页进入的。
      final isPublic =
          location == RoutePaths.login ||
          location == RoutePaths.deviceDiscovery;
      if (!authenticated && !isPublic) {
        return RoutePaths.login;
      }
      if (authenticated && location == RoutePaths.login) {
        return RoutePaths.media;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.splash,
        pageBuilder: (context, state) => _plainPage(const SplashPage()),
      ),
      GoRoute(
        path: RoutePaths.login,
        pageBuilder: (context, state) => _plainPage(const LoginPage()),
      ),
      GoRoute(
        path: RoutePaths.deviceDiscovery,
        pageBuilder: (context, state) =>
            _pushPage(context, state, const DeviceSelectPage()),
      ),
      GoRoute(
        path: RoutePaths.media,
        pageBuilder: (context, state) =>
            _plainPage(const _TabHost(tab: MainTab.media)),
        routes: <RouteBase>[
          _detailRoute(
            builder: (context, state, id) => MediaDetailPage(id: id),
          ),
          // 播放页走淡入淡出：它是全屏内容页，横向滑动在播放器里另有含义。
          GoRoute(
            path: 'player',
            pageBuilder: (context, state) {
              final extra = state.extra;
              return _fadePage(
                context,
                state,
                MediaPlayerPage(
                  args: extra is MediaPlayerArgs ? extra : null,
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.people,
        pageBuilder: (context, state) =>
            _plainPage(const _TabHost(tab: MainTab.people)),
        routes: <RouteBase>[
          _detailRoute(
            builder: (context, state, id) => PeopleDetailPage(id: id),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.novel,
        pageBuilder: (context, state) =>
            _plainPage(const _TabHost(tab: MainTab.novel)),
        routes: <RouteBase>[
          _detailRoute(
            builder: (context, state, id) => NovelDetailPage(id: id),
          ),
          GoRoute(
            path: 'detail/read',
            pageBuilder: (context, state) => _fadePage(
              context,
              state,
              NovelReaderPage(
                bookId: state.uri.queryParameters['bookId'] ?? '',
                chapterId: state.uri.queryParameters['chapterId'],
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.comic,
        pageBuilder: (context, state) =>
            _plainPage(const _TabHost(tab: MainTab.comic)),
        routes: <RouteBase>[
          _detailRoute(
            builder: (context, state, id) => ComicDetailPage(id: id),
          ),
          GoRoute(
            path: 'detail/read',
            pageBuilder: (context, state) => _fadePage(
              context,
              state,
              ComicReaderPage(
                albumId: state.uri.queryParameters['albumId'] ?? '',
                chapterId: state.uri.queryParameters['chapterId'],
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.management,
        pageBuilder: (context, state) =>
            _pushPage(context, state, const ManagementPage()),
      ),
      // 兼容直接访问 /main
      GoRoute(
        path: RoutePaths.mainRoot,
        redirect: (context, state) => RoutePaths.media,
      ),
    ],
    errorBuilder: (context, state) =>
        _RouteNotFound(location: state.uri.toString()),
  );
});

/// 无转场页面：用于顶级 Tab 与开屏 / 登录页。
Page<void> _plainPage(Widget child) => NoTransitionPage<void>(child: child);

/// 层级子页面：从右侧滑入 + 淡入。
Page<void> _pushPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => CustomTransitionPage<void>(
  key: state.pageKey,
  transitionDuration: AppMotion.normal,
  reverseTransitionDuration: AppMotion.normal,
  child: child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.standard,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  },
);

/// 全屏内容页面（阅读器）：淡入淡出。
///
/// 阅读器会切换到沉浸式全屏，左右滑动在漫画阅读器里另有含义，
/// 因此不使用横向滑动转场。
Page<void> _fadePage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => CustomTransitionPage<void>(
  key: state.pageKey,
  transitionDuration: AppMotion.slow,
  reverseTransitionDuration: AppMotion.fast,
  child: child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(opacity: animation, child: child),
);

GoRoute _detailRoute({
  required Widget Function(BuildContext context, GoRouterState state, String id)
  builder,
}) => GoRoute(
  path: 'detail',
  pageBuilder: (context, state) => _pushPage(
    context,
    state,
    builder(context, state, state.uri.queryParameters['id'] ?? ''),
  ),
);

/// 主界面宿主：保持选中 Tab 的同时承载主界面。
class _TabHost extends StatelessWidget {
  const _TabHost({required this.tab});

  final MainTab tab;

  @override
  Widget build(BuildContext context) => MainShellHost(tab: tab);
}

class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      AppLogger.warning('AppRouter', 'no route registered for $location');
    }
    return Scaffold(
      body: Center(
        child: Text(
          '404 · $location',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// 把启动状态与认证状态的变化桥接为 GoRouter 的刷新信号。
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(BootstrapManager manager) {
    _subscription = manager.stateStream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<BootstrapState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// 内容类型到路由的扩展。
extension ContentKindRoutePath on ContentKind {
  /// 页面路由。
  String get route => switch (this) {
    ContentKind.media => RoutePaths.media,
    ContentKind.people => RoutePaths.people,
    ContentKind.novel => RoutePaths.novel,
    ContentKind.comic => RoutePaths.comic,
  };
}
