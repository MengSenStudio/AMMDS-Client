import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_container.dart';
import '../../../../app/route_paths.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/entities/splash.dart';
import '../../../../domain/services/bootstrap_manager.dart';
import '../../../../shared/widgets/app_logo_3d.dart';

/// 开屏页面（文档 #14 / #65）。
///
/// 页面结构固定为 4:1 两段：
///
/// ```text
/// ┌──────────────────────────┐
/// │                          │
/// │        品牌区 4/5        │  官方：3D Logo（或静态页）
/// │                          │  广告：广告图 + 右上角「跳过」
/// ├──────────────────────────┤
/// │      产品名称（主标题）    │  品牌区 1/5
/// │      版权等小灰字         │
/// └──────────────────────────┘
/// ```
///
/// 关键约定：
/// * **只有广告开屏展示跳过按钮**，AMMDS 官方开屏不允许跳过；
/// * 页面的唯一职责是「展示 + 决定去主界面还是登录页」，
///   初始化逻辑全部由 [BootstrapManager] 承担；
/// * 页面是离开开屏的**唯一**决策方（路由不再自行跳转），
///   因此可以保证官方动画至少展示 [_officialMinDuration]，不会一闪而过。
class SplashPage extends ConsumerStatefulWidget {
  /// 创建页面。
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  /// 官方开屏至少展示的时长（品牌动画需要被看清）。
  static const Duration _officialMinDuration = AppMotion.splash;

  /// 兜底超时：无论初始化是否完成，超过该时长都进入登录页。
  static const Duration _guardTimeout = Duration(seconds: 12);

  final DateTime _enteredAt = DateTime.now();

  StreamSubscription<BootstrapState>? _bootstrapSubscription;
  Timer? _exitTimer;
  Timer? _skipTimer;
  Timer? _guardTimer;

  SplashConfig? _config;
  bool _bootstrapCompleted = false;
  bool _configResolved = false;
  bool _adImageFailed = false;
  bool _navigated = false;
  bool _initialized = false;

  /// 距离可跳过还剩的秒数（仅广告使用）。
  int _skipCountdown = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    final l10n = context.l10n;
    _config = SplashConfig.local(
      productName: l10n.appName,
      copyright: l10n.appCopyright,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    _skipTimer?.cancel();
    _guardTimer?.cancel();
    unawaited(_bootstrapSubscription?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted) {
      return;
    }
    _guardTimer = Timer(_guardTimeout, _navigate);
    _listenBootstrap();
    unawaited(_resolveConfig());
    final bootstrap = ref.read(bootstrapManagerProvider);
    if (!bootstrap.state.isCompleted) {
      unawaited(bootstrap.start());
    }
  }

  /// 订阅启动状态（广播流可能已经发出过事件，因此同时检查当前状态）。
  void _listenBootstrap() {
    final bootstrap = ref.read(bootstrapManagerProvider);
    _bootstrapSubscription = bootstrap.stateStream.listen((state) {
      if (state.isCompleted) {
        _onBootstrapCompleted();
      }
    });
    if (bootstrap.state.isCompleted) {
      _onBootstrapCompleted();
    }
  }

  void _onBootstrapCompleted() {
    if (_bootstrapCompleted) {
      return;
    }
    _bootstrapCompleted = true;
    _scheduleExit();
  }

  /// 解析开屏配置：服务端下发优先，失败/未配置时保持本地官方开屏。
  Future<void> _resolveConfig() async {
    final l10n = context.l10n;
    final local = SplashConfig.local(
      productName: l10n.appName,
      copyright: l10n.appCopyright,
    );
    var resolved = local;
    // 开屏早于任何界面交互，直接读管理器的当前值（同步、必定是最新已加载的档案），
    // 避免依赖异步 Provider 的首个事件。
    final server = ref.read(serverManagerProvider).activeServer;
    if (server != null) {
      resolved = await ref
          .read(serverRepositoryProvider)
          .fetchSplashConfig(
            server,
            fallbackProductName: l10n.appName,
            fallbackCopyright: l10n.appCopyright,
          );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _config = resolved;
      _configResolved = true;
    });
    _scheduleExit();
  }

  /// 启动完成且配置就绪后，安排离开开屏的时间点。
  void _scheduleExit() {
    if (_navigated || !_bootstrapCompleted || !_configResolved) {
      return;
    }
    final config = _config;
    if (config == null) {
      return;
    }
    if (!config.isAd) {
      final elapsed = DateTime.now().difference(_enteredAt);
      final remaining = _officialMinDuration - elapsed;
      _exitTimer = Timer(
        remaining > Duration.zero ? remaining : Duration.zero,
        _navigate,
      );
      return;
    }
    // 广告：展示满 durationMs 后自动结束；可跳过时间用倒计时呈现。
    final skipAfter = Duration(milliseconds: config.skipAfterMs);
    _skipCountdown = (skipAfter.inMilliseconds / 1000).ceil();
    if (_skipCountdown > 0) {
      _skipTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _skipCountdown -= 1);
        if (_skipCountdown <= 0) {
          timer.cancel();
        }
      });
    }
    _exitTimer = Timer(
      Duration(milliseconds: config.durationMs),
      _navigate,
    );
  }

  /// 离开开屏页：进入主界面或登录页。
  void _navigate() {
    if (_navigated || !mounted) {
      return;
    }
    _navigated = true;
    _exitTimer?.cancel();
    _skipTimer?.cancel();
    _guardTimer?.cancel();
    final destination = ref.read(bootstrapManagerProvider).state.destination;
    AppLogger.info(
      'SplashPage',
      'leaving splash → ${destination?.name ?? 'login'}',
    );
    context.go(
      destination == BootstrapDestination.main
          ? RoutePaths.media
          : RoutePaths.login,
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (config == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: config.isAd ? Colors.black : colors.background,
      body: Column(
        children: <Widget>[
          Expanded(flex: 4, child: _buildBrandArea(config)),
          Expanded(flex: 1, child: _buildFooter(config)),
        ],
      ),
    );
  }

  /// 品牌区：官方 Logo 或广告图（含跳过按钮）。
  Widget _buildBrandArea(SplashConfig config) {
    if (config.isAd && !_adImageFailed) {
      return _buildAd(config);
    }
    return _buildOfficialLogo(config);
  }

  Widget _buildOfficialLogo(SplashConfig config) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = <double>[
          constraints.maxWidth * 0.46,
          constraints.maxHeight * 0.72,
          240,
        ].reduce((a, b) => a < b ? a : b);
        return Center(
          child: AppLogo3D(
            size: size,
            motion: config.officialStyle == SplashOfficialStyle.static
                ? LogoMotion.static
                : LogoMotion.zoom,
            // 动画时长与开屏最短展示时长一致：缩放时间线收束的瞬间开屏关闭。
            duration: _officialMinDuration,
            showProgress: true,
          ),
        );
      },
    );
  }

  Widget _buildAd(SplashConfig config) {
    final imageUrl = config.imageUrl;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (imageUrl != null)
          Image.network(
            imageUrl.toString(),
            fit: BoxFit.cover,
            // 广告图不可达时回落为官方开屏，避免开屏变成空白页
            errorBuilder: (context, error, stackTrace) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_adImageFailed) {
                  setState(() => _adImageFailed = true);
                }
              });
              return const SizedBox.shrink();
            },
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                return child;
              }
              return const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              );
            },
          ),
        // 只有广告开屏展示跳过按钮
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _SkipButton(
                countdown: _skipCountdown,
                enabled: _skipCountdown <= 0,
                onTap: _navigate,
              ),
            ),
          ),
        ),
        if (config.title != null && config.title!.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xxl,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.transparent, Color(0xB3000000)],
                ),
              ),
              child: Text(
                config.title!,
                style: AppTypography.body.copyWith(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  /// 底部 1/5：产品名称（主标题）+ 版权等小灰字。
  Widget _buildFooter(SplashConfig config) {
    final colors = context.appColors;
    final onDark = config.isAd && !_adImageFailed;
    final titleColor = onDark ? Colors.white : colors.textPrimary;
    final subtitleColor = onDark ? Colors.white70 : colors.textTertiary;
    final bootstrap = ref.watch(bootstrapStateProvider).value;
    final stage = bootstrap?.stage ?? BootstrapStage.idle;
    // 启动未完成时，小灰字用于反馈当前阶段；完成后展示版权信息。
    final subtitle = stage == BootstrapStage.completed
        ? config.copyright
        : _stageLabel(context, stage);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              config.productName,
              textAlign: TextAlign.center,
              style: AppTypography.headline.copyWith(color: titleColor),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: subtitleColor),
            ),
          ],
        ),
      ),
    );
  }

  static String _stageLabel(BuildContext context, BootstrapStage stage) {
    final l10n = context.l10n;
    return switch (stage) {
      BootstrapStage.loadingConfig => l10n.bootstrapLoadingConfig,
      BootstrapStage.initializingStorage => l10n.bootstrapInitializingStorage,
      BootstrapStage.initializingNetwork => l10n.bootstrapInitializingNetwork,
      BootstrapStage.restoringSession => l10n.bootstrapRestoringSession,
      BootstrapStage.connectingServer => l10n.bootstrapConnectingServer,
      _ => l10n.bootstrapInitializing,
    };
  }
}

/// 广告开屏的跳过按钮。
///
/// 仅在 [_SplashPageState] 判定为广告类型时才会出现在右上角。
class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.countdown,
    required this.enabled,
    required this.onTap,
  });

  /// 剩余秒数，大于 0 时展示倒计时且不可点击。
  final int countdown;

  /// 是否可跳过。
  final bool enabled;

  /// 点击跳过。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = enabled
        ? context.l10n.splashSkip
        : context.l10n.splashSkipCountdown(countdown);
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: enabled ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
