import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_assets.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_theme.dart';

/// 官方品牌标识的呈现方式。
enum LogoMotion {
  /// 缩放呼吸。
  ///
  /// 进入时淡入并放大（0.86 → 1.0），随后缓慢放大到 1.08 再回落到常态，
  /// 整条时间线与开屏展示时长一致，**离场时动画刚好收束**。
  ///
  /// 刻意不做旋转：位图绕 Y 轴转动会带来投影宽度收缩与「忽大忽小」的观感。
  zoom,

  /// 静态展示（不做任何持续动画）。
  static,
}

/// 品牌 Logo。
///
/// 资源为透明背景的 `logo_header.png`（见 [AppAssets]），
/// 呈现方式由 [LogoMotion] 决定：
///
/// * [LogoMotion.zoom]：淡入 + 缩放呼吸（一次性，时长与开屏一致）；
/// * [LogoMotion.static]：只有一次性淡入。
class AppLogo3D extends StatefulWidget {
  /// 创建组件。
  const AppLogo3D({
    super.key,
    this.size = 180,
    this.motion = LogoMotion.zoom,
    this.duration = AppMotion.splash,
    this.showProgress = false,
    this.onLoaded,
  });

  /// 视觉尺寸（正方形边长）。
  final double size;

  /// 呈现方式。
  final LogoMotion motion;

  /// 动画总时长；默认与开屏展示时长一致，保证动画刚好在离场时收束。
  final Duration duration;

  /// 资源加载期间是否展示进度指示。
  final bool showProgress;

  /// 资源加载完成回调。
  final VoidCallback? onLoaded;

  @override
  State<AppLogo3D> createState() => AppLogo3DState();
}

/// [AppLogo3D] 状态，暴露加载状态供启动流程判断。
class AppLogo3DState extends State<AppLogo3D>
    with SingleTickerProviderStateMixin {
  /// 淡入所占的时间比例。
  static const double _fadeEnd = 0.30;

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  ui.Image? _logo;
  bool _failed = false;

  /// 品牌资源是否已就绪。
  bool get isReady => _logo != null;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, _fadeEnd, curve: Curves.easeOut),
    );
    _scale = TweenSequence<double>(
      <TweenSequenceItem<double>>[
        // 入场：由略小放大到常态
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 0.86,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeOutCubic)),
          weight: _fadeEnd * 100,
        ),
        // 中段：缓慢放大
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1,
            end: 1.08,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 48,
        ),
        // 收束：回落到常态，恰好与开屏离场对齐
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1.08,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 22,
        ),
      ],
    ).animate(_controller);
    if (widget.motion == LogoMotion.zoom) {
      _controller.forward();
    } else {
      _controller.value = _fadeEnd;
    }
    _loadAssets();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    try {
      final data = await rootBundle.load(AppAssets.logoHeader);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) {
        return;
      }
      setState(() => _logo = frame.image);
      widget.onLoaded?.call();
    } on Object catch (error) {
      AppLogger.warning('AppLogo3D', 'brand asset load failed', error);
      if (!mounted) {
        return;
      }
      setState(() => _failed = true);
      widget.onLoaded?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final logo = _logo;
    if (logo == null || _failed) {
      return _buildLoading(context);
    }
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(scale: _scale, child: _buildLogo(logo)),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: widget.showProgress
            ? SizedBox(
                width: widget.size * 0.16,
                height: widget.size * 0.16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: colors.brand,
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildLogo(ui.Image logo) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: RawImage(image: logo, fit: BoxFit.contain),
  );
}
