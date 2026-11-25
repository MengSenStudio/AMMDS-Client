import 'dart:async';

import 'package:flutter/gestures.dart'
    show kDoubleTapSlop, kDoubleTapTimeout, kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/app_container.dart';
import '../../../../app/navigation.dart';
import '../../../../app/route_paths.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/entities/content.dart';
import '../../../../shared/states/async_state.dart' show localizeError;

/// 播放页入参。
///
/// 通过 go_router 的 `extra` 传递（而不是塞进 URL），
/// 因为「可播放文件清单」不适合作为地址栏参数。
final class MediaPlayerArgs {
  /// 创建入参。
  const MediaPlayerArgs({
    required this.title,
    required this.files,
    required this.fileId,
  });

  /// 影视标题。
  final String title;

  /// 可播放文件清单（调用方过滤掉不可用项）。
  final List<MediaFile> files;

  /// 初始播放的文件标识。
  final String fileId;
}

/// 影视播放页。
///
/// 播放前先向服务端请求「播放能力决策」（把本机解码能力上报，由服务端决定
/// 直接播放 / 重封装 / 转码 / 不可播放）：
///
/// ```text
/// 选择播放源 → 能力决策请求
///   ├─ direct / remux → 打开视频流（支持 Range 拖动）
///   └─ unsupported    → 展示服务端给出的原因（不假装能播）
/// ```
///
/// 播放地址是「服务端根地址 + 决策返回的相对路径 + 访问令牌」：
/// `<video>` 无法自定义请求头，因此服务端额外支持用 `?token=` 传递令牌
/// （见服务端 `ClientMediaPlaybackController`）。
///
/// 播放器能力（对齐常见播放器）：
///
/// * **操作栏自动隐藏**：3 秒无操作即收起顶部标题栏与底部控制条——播放中、
///   暂停、缓冲、播放结束一视同仁；点击画面、滑动画面、移动鼠标或任意
///   快捷键都会重新唤出；
/// * **画面手势**（触屏与鼠标通用）：
///   - 单击画面：播放 / 暂停，并唤出操作栏；
///   - 双击画面左 / 右半屏：后退 / 前进 10 秒；
///   - 画面横向滑动：拖动定位进度（满屏宽度 ≈ 整段时长，与进度条刻度一致）；
///   - 画面左半屏上下滑动：调整亮度；右半屏上下滑动：调整音量；
/// * 进度条可拖动定位，另提供 ±10 秒快捷进退；
/// * 音量滑杆与静音；倍速（0.5x ~ 2x）；
/// * 键盘：空格 / K 播放暂停，← → 快退快进，↑ ↓ 音量，M 静音；
/// * **播放源**：同一部影视可能有多个视频文件（分集 / 分段 / 多目录），
///   当前源常显在标题下方，随时可在「播放源」弹层里查看全部源并切换。
///
/// 亮度说明：左半屏上下滑动通过原生插件（`screen_brightness`）调整屏幕亮度，
/// 离开播放页时恢复进入前的亮度。插件不支持的平台（如 Web / Linux）直接忽略，
/// 不做降级补偿——手势本身与浮层反馈在所有平台都保留。
///
/// 布局说明：顶部标题栏与底部控制条**不叠在画面上**（见 `AnimatedSize`），
/// 收起时把高度让给视频；只有手势浮层这类瞬时反馈绘制在画面之上。
class MediaPlayerPage extends ConsumerStatefulWidget {
  /// 创建页面。
  ///
  /// [args] 为空表示没有拿到播放入参（例如异常进入），页面会给出明确提示。
  const MediaPlayerPage({super.key, this.args});

  /// 播放入参。
  final MediaPlayerArgs? args;

  @override
  ConsumerState<MediaPlayerPage> createState() => _MediaPlayerPageState();
}

class _MediaPlayerPageState extends ConsumerState<MediaPlayerPage> {
  /// 播放中无操作后自动收起操作栏的延迟。
  static const Duration _chromeHideDelay = Duration(seconds: 3);

  /// 快捷键快进 / 快退步长。
  static const Duration _seekStep = Duration(seconds: 10);

  /// 音量快捷键步长。
  static const double _volumeStep = 0.05;

  /// 宽屏阈值：达到后音量以滑杆常驻，否则只保留静音按钮
  /// （移动端音量本就由硬件按键控制）。
  static const double _wideLayoutWidth = 700;

  /// 倍速候选。
  static const List<double> _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// 亮度下限：避免滑到全黑看不见画面。
  static const double _minBrightness = 0.1;

  /// 手势浮层停留时长。
  static const Duration _hudHold = Duration(milliseconds: 900);

  /// 上下滑动的换算基准：滑过「画面高度的 70%」等于走完整个可调区间。
  static const double _verticalDragSpan = 0.7;

  /// 单击 / 双击的判定窗口（与框架的 `kDoubleTapTimeout` 一致）。
  static const Duration _doubleTapWindow = kDoubleTapTimeout;

  VideoPlayerController? _controller;
  MediaFile? _current;
  bool _preparing = true;
  String? _blockedReason;
  Object? _error;

  /// 操作栏是否可见（无操作一段时间后自动收起）。
  bool _chromeVisible = true;
  Timer? _chromeTimer;

  /// 拖动进度条时的临时位置（毫秒）；为空表示未在拖动。
  double? _dragMillis;

  /// 横向滑动定位时的目标位置（毫秒）；为空表示未在定位。
  double? _scrubMillis;

  /// 音量（0~1）与静音标记：静音时保留滑杆位置，取消静音可原样恢复。
  double _volume = 1;
  bool _muted = false;

  /// 屏幕亮度（[_minBrightness] ~ 1），由原生插件落地；插件不可用时仅作为浮层读数。
  double _brightness = 1;

  /// 倍速。
  double _speed = 1;

  /// 手势浮层（音量 / 亮度 / 定位反馈）；为空表示不显示。
  _HudInfo? _hud;
  Timer? _hudTimer;

  /// 单击判定计时器。
  ///
  /// 单击 / 双击不走框架的 `GestureDetector.onTap` / `onDoubleTap`：两者同时注册时
  /// 框架把单击判定推迟到双击超时之后，且**按下不足 100ms 的快速点击**
  /// （鼠标单击的典型时长）不会触发任何回调，单击会静默失效。
  /// 因此这里直接按原始指针事件判定，见 [_onStagePointerUp]。
  Timer? _tapTimer;

  /// 主指针（多指时只认第一根手指）。
  int? _pointer;

  /// 按下位置与「是否已越过点击容差」（越过即交给拖动）。
  Offset _downPosition = Offset.zero;
  bool _movedBeyondSlop = false;

  /// 上一击的时间 / 位置，以及本次按下是否构成双击。
  Duration? _lastTapAt;
  Offset? _lastTapPosition;
  bool _isDoubleTap = false;

  /// 上一次的播放 / 缓冲状态：发生跳变（起播、暂停、缓冲进出、播放结束）时
  /// 重新计时，让操作栏继续按「无操作 3 秒」的规则自动收起。
  bool _wasPlaying = false;
  bool _wasBuffering = false;

  /// 是否已处理过「播放结束」。
  ///
  /// 部分平台（尤其移动端）在播放结束后仍会持续上报末尾位置，甚至把位置
  /// 回退到 0：若照旧每次通知都 `setState`，末帧会被反复重建，画面在末帧与
  /// 首帧之间闪动（进度条也会来回跳）。因此完成态只处理一次，之后的重复
  /// 通知直接忽略，直到用户重新播放或拖动进度（见 [_resumeTicking]）。
  bool _ended = false;

  final FocusNode _focusNode = FocusNode(debugLabel: 'media-player');

  List<MediaFile> get _files => widget.args?.files ?? const <MediaFile>[];

  /// 是否已进入可播放状态。
  bool get _ready {
    final controller = _controller;
    return controller != null &&
        controller.value.isInitialized &&
        _blockedReason == null &&
        _error == null;
  }

  bool get _playing => _controller?.value.isPlaying ?? false;

  bool get _buffering => _controller?.value.isBuffering ?? false;

  double get _effectiveVolume => _muted ? 0 : _volume;

  @override
  void initState() {
    super.initState();
    final args = widget.args;
    if (args == null || args.files.isEmpty) {
      _preparing = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusNode.requestFocus();
      unawaited(_loadBrightness());
      unawaited(_prepare(args.fileId));
    });
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _hudTimer?.cancel();
    _tapTimer?.cancel();
    _focusNode.dispose();
    unawaited(_resetBrightness());
    unawaited(_controller?.dispose());
    super.dispose();
  }

  /// 读取当前屏幕亮度作为起点。
  ///
  /// 插件不支持的平台会抛异常，这里直接忽略并沿用默认值（不做降级补偿）。
  Future<void> _loadBrightness() async {
    try {
      final value = await ScreenBrightness.instance.application;
      if (!mounted || !value.isFinite) {
        return;
      }
      setState(() => _brightness = value.clamp(_minBrightness, 1.0));
    } on Object catch (error) {
      AppLogger.debug(
        'MediaPlayerPage',
        'read screen brightness skipped: ${AppLogger.sanitize('$error')}',
      );
    }
  }

  /// 写入屏幕亮度；插件不支持或调用失败时忽略。
  Future<void> _applyBrightness(double value) async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(value);
    } on Object catch (error) {
      AppLogger.debug(
        'MediaPlayerPage',
        'set screen brightness skipped: ${AppLogger.sanitize('$error')}',
      );
    }
  }

  /// 离开播放页时恢复进入前的亮度；插件不支持时忽略。
  Future<void> _resetBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } on Object catch (error) {
      AppLogger.debug(
        'MediaPlayerPage',
        'reset screen brightness skipped: ${AppLogger.sanitize('$error')}',
      );
    }
  }

  Future<void> _prepare(String fileId) async {
    final target = _files.firstWhere(
      (file) => file.id == fileId,
      orElse: () => _files.first,
    );
    _chromeTimer?.cancel();
    _hudTimer?.cancel();
    _cancelPendingTap();
    await _controller?.dispose();
    if (!mounted) {
      return;
    }
    setState(() {
      _current = target;
      _controller = null;
      _preparing = true;
      _blockedReason = null;
      _error = null;
      _dragMillis = null;
      _scrubMillis = null;
      _hud = null;
      _chromeVisible = true;
      _wasPlaying = false;
      _wasBuffering = false;
      _ended = false;
    });
    try {
      // 1) 能力决策：由服务端判断是否可以播放
      final decision = await ref
          .read(contentRepositoryProvider)
          .playbackDecision(target.id);
      if (!mounted) {
        return;
      }
      if (!decision.mode.isPlayable || decision.url == null) {
        setState(() {
          _preparing = false;
          _blockedReason = decision.reason ?? context.l10n.playerUnavailable;
        });
        return;
      }

      // 2) 附加访问令牌并打开视频流
      final token = await ref
          .read(sessionManagerProvider)
          .currentAccessToken();
      final uri = Uri.parse(decision.url!).replace(
        queryParameters: <String, String>{
          if (token != null && token.isNotEmpty) 'token': token,
        },
      );
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onPlayerTick);
      // 切换播放源后沿用用户已经调好的音量与倍速
      await controller.setVolume(_effectiveVolume);
      await controller.setPlaybackSpeed(_speed);
      await controller.play();
      if (!mounted) {
        return;
      }
      setState(() {
        _controller = controller;
        _preparing = false;
      });
      _focusNode.requestFocus();
      _scheduleChromeHide();
    } on Object catch (error) {
      AppLogger.warning('MediaPlayerPage', 'prepare playback failed', error);
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _preparing = false;
      });
    }
  }

  void _onPlayerTick() {
    if (!mounted) {
      return;
    }
    final value = _controller?.value;
    if (value == null) {
      return;
    }
    if (_isEnded(value)) {
      // 完成态只处理一次：之后的重复通知不再重建界面，避免末帧被反复刷成
      // 首帧（画面闪动、进度条乱跳）。
      if (_ended) {
        return;
      }
      _ended = true;
      // 部分移动端平台在播放结束后会自动把位置回退到 0 并继续解码，导致
      // 画面在末帧与首帧之间闪动。这里主动 pause + seek 到末尾，强迫平台
      // 停止解码并稳定显示末帧。
      final controller = _controller;
      if (controller != null) {
        unawaited(controller.pause());
        if (value.duration > Duration.zero) {
          unawaited(controller.seekTo(value.duration));
        }
      }
      _scheduleChromeHide();
      setState(() {});
      return;
    }
    if (_ended && !value.isPlaying) {
      // 已结束且未重新播放：忽略平台上报的位置回退，保持在末帧。
      // 注意：不要在这里调用 _resumeTicking()，否则平台把 isPlaying 短暂
      // 置为 true 时会立刻清除 _ended，下一帧 _isEnded 再设回 true，
      // 形成反复重建画面的闪动循环。_ended 只在用户主动操作
      // （[_togglePlay] / [_onScrubEnd] / [_seekBy]）时由 _resumeTicking 清除。
      return;
    }
    // 正常播放中：状态跳变时重新计时操作栏隐藏。
    if (value.isPlaying != _wasPlaying || value.isBuffering != _wasBuffering) {
      _wasPlaying = value.isPlaying;
      _wasBuffering = value.isBuffering;
      _scheduleChromeHide();
    }
    setState(() {});
  }

  /// 是否已停在片尾（位置到达总时长且不再播放）。
  static bool _isEnded(VideoPlayerValue value) {
    final duration = value.duration;
    return !value.isPlaying &&
        duration > Duration.zero &&
        value.position >= duration;
  }

  /// 退出「完成态」：重新播放或用户主动定位后恢复逐帧刷新。
  void _resumeTicking() {
    _ended = false;
  }

  /// 唤出操作栏并重新计时。
  ///
  /// 鼠标移动会高频触发，因此只在「由隐藏变可见」时才重建。
  void _bumpChrome() {
    final wasVisible = _chromeVisible;
    _chromeVisible = true;
    _scheduleChromeHide();
    if (!wasVisible) {
      setState(() {});
    }
  }

  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(_chromeHideDelay, () {
      if (mounted) {
        setState(() => _chromeVisible = false);
      }
    });
  }

  /// 按下：记录起点，并判断本次是否构成双击。
  void _onStagePointerDown(PointerDownEvent event) {
    if (_pointer != null) {
      return;
    }
    _pointer = event.pointer;
    _downPosition = event.localPosition;
    _movedBeyondSlop = false;
    final lastAt = _lastTapAt;
    final lastPosition = _lastTapPosition;
    _isDoubleTap =
        lastAt != null &&
        lastPosition != null &&
        event.timeStamp - lastAt <= _doubleTapWindow &&
        (event.localPosition - lastPosition).distance <= kDoubleTapSlop;
    if (_isDoubleTap) {
      // 第二次按下：上一个单击作废
      _lastTapAt = null;
      _lastTapPosition = null;
      _cancelPendingTap();
    }
  }

  /// 移动：越过点击容差即视为拖动（滑动定位 / 音量亮度），不再算点击。
  void _onStagePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _confirmDrag(event.localPosition);
  }

  /// 抬起：双击直接快进 / 快退；单击延迟一个双击判定窗口后播放 / 暂停。
  void _onStagePointerUp(PointerUpEvent event, Size stage) {
    if (event.pointer != _pointer) {
      return;
    }
    final position = event.localPosition;
    final doubleTap = _isDoubleTap;
    _pointer = null;
    _isDoubleTap = false;
    if (_movedBeyondSlop) {
      return;
    }
    if (doubleTap) {
      unawaited(_doubleTapSeek(position, stage));
      return;
    }
    _lastTapAt = event.timeStamp;
    _lastTapPosition = position;
    _cancelPendingTap();
    _tapTimer = Timer(_doubleTapWindow, () {
      _tapTimer = null;
      _lastTapAt = null;
      _lastTapPosition = null;
      if (mounted) {
        unawaited(_togglePlay());
      }
    });
  }

  /// 指针被系统取消（如被浏览器接管）：丢弃本次点击。
  void _onStagePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    _isDoubleTap = false;
    _cancelPendingTap();
  }

  void _cancelPendingTap() {
    _tapTimer?.cancel();
    _tapTimer = null;
  }

  /// 确认本次指针已移出点击容差，可以算作拖动。
  ///
  /// 鼠标单击时常有几像素抖动，未越过容差就不该被当成滑动定位；
  /// 判定只依赖「按下位置到当前位置的距离」，不依赖回调顺序，
  /// 且一旦成立，本次指针序列内保持成立。
  bool _confirmDrag(Offset position) {
    if (_movedBeyondSlop) {
      return true;
    }
    if ((position - _downPosition).distance <= kTouchSlop) {
      return false;
    }
    _movedBeyondSlop = true;
    // 已成为拖动：不会再与上一次点击组成双击，待判定的单击也作废
    _isDoubleTap = false;
    _lastTapAt = null;
    _lastTapPosition = null;
    _cancelPendingTap();
    return true;
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    // 从完成态重新播放：先解除「已结束」的静默，让进度条随播放继续刷新。
    _resumeTicking();
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    _bumpChrome();
  }

  /// 双击画面：落点在左半屏快退、右半屏快进，并给出浮层反馈。
  Future<void> _doubleTapSeek(Offset position, Size stage) async {
    _cancelPendingTap();
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final forward = position.dx >= stage.width / 2;
    final before = controller.value.position;
    await _seekBy(forward ? _seekStep : -_seekStep, bumpChrome: false);
    final value = controller.value;
    _showHud(
      _HudInfo.seek(
        position: value.position,
        duration: value.duration,
        delta: value.position - before,
      ),
    );
  }

  /// 横向滑动开始：先记下基准位置。
  ///
  /// 是否真的算「滑动定位」由 [_onScrubUpdate] 按点击容差裁定，
  /// 因此这里不产生任何可见反馈。
  void _onScrubStart() {
    final controller = _controller;
    if (controller == null || controller.value.duration <= Duration.zero) {
      return;
    }
    _scrubMillis = controller.value.position.inMilliseconds.toDouble();
  }

  /// 横向滑动：按「满屏宽度 ≈ 整段时长」换算目标位置（与进度条刻度一致）。
  void _onScrubUpdate(DragUpdateDetails details, Size stage) {
    if (!_confirmDrag(details.localPosition)) {
      return;
    }
    final controller = _controller;
    final current = _scrubMillis;
    if (controller == null || current == null) {
      return;
    }
    final duration = controller.value.duration;
    final total = duration.inMilliseconds.toDouble();
    if (total <= 0 || stage.width <= 0) {
      return;
    }
    final next = (current + details.delta.dx / stage.width * total).clamp(
      0.0,
      total,
    );
    _scrubMillis = next;
    _bumpChrome();
    _showHud(
      _HudInfo.seek(
        position: Duration(milliseconds: next.round()),
        duration: duration,
        delta: Duration.zero,
      ),
    );
  }

  /// 横向滑动结束：定位到目标位置。
  Future<void> _onScrubEnd() async {
    final controller = _controller;
    final target = _scrubMillis;
    _scrubMillis = null;
    // 未越过点击容差的「拖动」（鼠标单击抖动）：不定位
    if (controller == null || target == null || !_movedBeyondSlop) {
      return;
    }
    await controller.seekTo(Duration(milliseconds: target.round()));
    _resumeTicking();
    _bumpChrome();
  }

  /// 横向滑动被打断：放弃本次定位。
  void _onScrubCancel() {
    _scrubMillis = null;
    _hudTimer?.cancel();
    setState(() => _hud = null);
  }

  /// 上下滑动：向上为增大；落点在左半屏调亮度，右半屏调音量。
  void _onVerticalDragUpdate(DragUpdateDetails details, Size stage) {
    if (!_confirmDrag(details.localPosition)) {
      return;
    }
    final span = stage.height * _verticalDragSpan;
    if (span <= 0) {
      return;
    }
    final delta = -details.delta.dy / span;
    if (_downPosition.dx < stage.width / 2) {
      _adjustBrightness(delta);
    } else {
      unawaited(_adjustVolume(delta));
    }
  }

  /// 调整屏幕亮度（左半屏上下滑动）。
  ///
  /// 先更新读数与浮层，再异步把亮度写进原生插件——插件调用不阻塞手势反馈。
  void _adjustBrightness(double delta) {
    final next = (_brightness + delta).clamp(_minBrightness, 1.0);
    if (next != _brightness) {
      setState(() => _brightness = next);
      unawaited(_applyBrightness(next));
    }
    _showHud(
      _HudInfo.level(
        kind: _HudKind.brightness,
        level: _brightnessLevel(_brightness),
      ),
    );
  }

  /// 调整音量（右半屏上下滑动）：静音状态下以 0 为基准，滑动即解除静音。
  Future<void> _adjustVolume(double delta) async {
    final base = _muted ? 0.0 : _volume;
    final next = (base + delta).clamp(0.0, 1.0);
    await _setVolume(next, bumpChrome: false);
    _showHud(_HudInfo.level(kind: _HudKind.volume, level: next));
  }

  /// 显示手势浮层，并在 [MediaPlayerPage] 的停留时长后自动收起。
  void _showHud(_HudInfo info) {
    _hudTimer?.cancel();
    _hudTimer = Timer(_hudHold, () {
      if (mounted) {
        setState(() => _hud = null);
      }
    });
    setState(() => _hud = info);
  }

  Future<void> _seekBy(Duration delta, {bool bumpChrome = true}) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final value = controller.value;
    var target = value.position + delta;
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (value.duration > Duration.zero && target > value.duration) {
      target = value.duration;
    }
    await controller.seekTo(target);
    _resumeTicking();
    if (bumpChrome) {
      _bumpChrome();
    }
  }

  Future<void> _setVolume(double value, {bool bumpChrome = true}) async {
    final clamped = value.clamp(0.0, 1.0);
    setState(() {
      _volume = clamped;
      _muted = clamped == 0;
    });
    await _controller?.setVolume(_effectiveVolume);
    if (bumpChrome) {
      _bumpChrome();
    }
  }

  Future<void> _toggleMute() async {
    setState(() {
      if (_muted) {
        _muted = false;
        if (_volume == 0) {
          _volume = 0.8;
        }
      } else {
        _muted = true;
      }
    });
    await _controller?.setVolume(_effectiveVolume);
    _bumpChrome();
  }

  Future<void> _pickSpeed() async {
    _chromeTimer?.cancel();
    final selected = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SpeedSheet(options: _speeds, current: _speed),
    );
    if (selected != null && selected != _speed) {
      setState(() => _speed = selected);
      await _controller?.setPlaybackSpeed(selected);
    }
    _focusNode.requestFocus();
    _bumpChrome();
  }

  Future<void> _switchSource() async {
    _chromeTimer?.cancel();
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SourceSheet(
        files: _files,
        currentId: _current?.id,
      ),
    );
    _focusNode.requestFocus();
    if (selected != null && selected != _current?.id) {
      await _prepare(selected);
      return;
    }
    _bumpChrome();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (!_ready) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      unawaited(_togglePlay());
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_seekBy(-_seekStep));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_seekBy(_seekStep));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      unawaited(_setVolume((_muted ? 0 : _volume) + _volumeStep));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      unawaited(_setVolume((_muted ? 0 : _volume) - _volumeStep));
    } else if (key == LogicalKeyboardKey.keyM) {
      unawaited(_toggleMute());
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.args?.title ?? context.l10n.mediaPlayback;
    // 未就绪（准备中 / 不可播放 / 出错）时操作栏常显：此时页面里没有其它出口
    final persistent = !_ready;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: Column(
          children: <Widget>[
            _collapsible(
              visible: persistent || _chromeVisible,
              child: _buildTopChrome(context, title),
            ),
            Expanded(child: _buildStage(context)),
            _collapsible(
              visible: _ready && _chromeVisible,
              child: _buildBottomChrome(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 可收起的操作栏：收起时高度让给视频区。
  Widget _collapsible({required bool visible, required Widget child}) {
    return AnimatedSize(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: visible
          ? child
          : const SizedBox(width: double.infinity, height: 0),
    );
  }

  Widget _buildStage(BuildContext context) {
    if (_files.isEmpty) {
      return _buildBlocked(context, context.l10n.playerNoSource);
    }
    if (_preparing) {
      return _buildPreparing(context);
    }
    final blocked = _blockedReason;
    if (blocked != null) {
      return _buildBlocked(context, blocked);
    }
    final error = _error;
    if (error != null) {
      return _buildBlocked(context, localizeError(context, error));
    }
    final controller = _controller!;
    return MouseRegion(
      onHover: (_) => _bumpChrome(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stage = constraints.biggest;
          // 单击 / 双击用原始指针事件判定（见 [_onStagePointerDown] 的说明），
          // 拖动交给框架的拖动识别器，两者互不干扰。
          return Semantics(
            label: context.l10n.playerGestureHint,
            onTap: () => unawaited(_togglePlay()),
            child: Listener(
              onPointerDown: _onStagePointerDown,
              onPointerMove: _onStagePointerMove,
              onPointerUp: (event) => _onStagePointerUp(event, stage),
              onPointerCancel: _onStagePointerCancel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => _onScrubStart(),
                onHorizontalDragUpdate: (details) =>
                    _onScrubUpdate(details, stage),
                onHorizontalDragEnd: (_) => unawaited(_onScrubEnd()),
                onHorizontalDragCancel: _onScrubCancel,
                onVerticalDragUpdate: (details) =>
                    _onVerticalDragUpdate(details, stage),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Center(
                      child: AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: VideoPlayer(controller),
                      ),
                    ),
                    // 手势浮层：只作反馈，不接收指针事件。
                    if (_hud != null)
                      IgnorePointer(
                        child: Center(child: _buildHud(context, _hud!)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 手势浮层：音量 / 亮度百分比，或滑动定位的目标时间。
  Widget _buildHud(BuildContext context, _HudInfo hud) {
    final l10n = context.l10n;
    final icon = switch (hud.kind) {
      _HudKind.volume =>
        hud.level <= 0 ? TDIcons.sound_mute : TDIcons.sound_high,
      _HudKind.brightness => TDIcons.brightness,
      _HudKind.seek => hud.delta.isNegative
          ? TDIcons.chevron_left_double
          : TDIcons.chevron_right_double,
    };
    final level = hud.kind != _HudKind.seek;
    final primary = level
        ? '${(hud.level * 100).round()}%'
        : '${_format(hud.position)} / ${_format(hud.duration)}';
    final secondary = switch (hud.kind) {
      _HudKind.volume => l10n.playerVolume,
      _HudKind.brightness => l10n.playerBrightness,
      _HudKind.seek => _formatDelta(hud.delta),
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 168),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 22, color: Colors.white),
              const SizedBox(width: AppSpacing.sm),
              Text(
                primary,
                style: AppTypography.subtitle.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (level)
            SizedBox(
              width: 132,
              child: LinearProgressIndicator(
                value: hud.level,
                minHeight: 3,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            secondary,
            style: AppTypography.caption.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  /// 双击进退量的文案：`+10s` / `-10s`（顶到片头 / 片尾时差量为 0）。
  static String _formatDelta(Duration delta) {
    final seconds = delta.inSeconds;
    if (seconds == 0) {
      return '0s';
    }
    return '${seconds > 0 ? '+' : '-'}${seconds.abs()}s';
  }

  /// 亮度浮层用的比例：把 [_minBrightness] ~ 1 归一化到 0 ~ 1。
  static double _brightnessLevel(double brightness) =>
      ((brightness - _minBrightness) / (1 - _minBrightness)).clamp(0.0, 1.0);

  Widget _buildPreparing(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            context.l10n.playerPreparing,
            style: AppTypography.bodySmall.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildTopChrome(BuildContext context, String title) {
    final l10n = context.l10n;
    final source = _current?.displayTitle;
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => popOrGo(context, RoutePaths.media),
                icon: const Icon(
                  TDIcons.chevron_left,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.subtitle.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    if (source != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        '${l10n.playerSourceCurrent}：$source',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white60,
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
    );
  }

  Widget _buildBottomChrome(BuildContext context) {
    final l10n = context.l10n;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final value = controller.value;
    final duration = value.duration;
    final hasDuration = duration > Duration.zero;
    final position = _dragMillis == null
        ? value.position
        : Duration(milliseconds: _dragMillis!.round());
    final maxMillis = hasDuration ? duration.inMilliseconds.toDouble() : 1.0;
    final sliderValue = hasDuration
        ? position.inMilliseconds.clamp(0, maxMillis).toDouble()
        : 0.0;
    final style = AppTypography.caption.copyWith(color: Colors.white70);
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _wideLayoutWidth;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      if (_buffering) ...<Widget>[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Text(_format(position), style: style),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            thumbColor: Colors.white,
                            inactiveTrackColor: Colors.white24,
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: sliderValue,
                            max: maxMillis,
                            onChangeStart: hasDuration
                                ? (_) => _chromeTimer?.cancel()
                                : null,
                            onChanged: hasDuration
                                ? (milliseconds) => setState(
                                    () => _dragMillis = milliseconds,
                                  )
                                : null,
                            onChangeEnd: hasDuration
                                ? (milliseconds) async {
                                    setState(() => _dragMillis = null);
                                    await controller.seekTo(
                                      Duration(
                                        milliseconds: milliseconds.round(),
                                      ),
                                    );
                                    _resumeTicking();
                                    _bumpChrome();
                                  }
                                : null,
                          ),
                        ),
                      ),
                      Text(_format(duration), style: style),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      _chromeIcon(
                        _playing ? TDIcons.pause : TDIcons.play,
                        tooltip: _playing
                            ? l10n.playerPause
                            : l10n.playerPlay,
                        onTap: _togglePlay,
                        size: 26,
                      ),
                      _chromeIcon(
                        TDIcons.replay,
                        tooltip: l10n.playerBackward,
                        onTap: () => _seekBy(-_seekStep),
                      ),
                      _chromeIcon(
                        TDIcons.replay,
                        tooltip: l10n.playerForward,
                        onTap: () => _seekBy(_seekStep),
                        flip: true,
                      ),
                      const Spacer(),
                      // 静音开关 + 音量滑杆，宽窄屏都保留：
                      // 之前窄屏只放静音按钮，移动端用户没法拖动调音量，
                      // 只能点静音 / 取消静音。改为窄屏也带滑杆（更短）。
                      _chromeIcon(
                        _muted ? TDIcons.sound_mute : TDIcons.sound_high,
                        tooltip: _muted
                            ? l10n.playerUnmute
                            : l10n.playerMute,
                        onTap: _toggleMute,
                      ),
                      Tooltip(
                        message: l10n.playerVolume,
                        child: SizedBox(
                          width: wide ? 110 : 72,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.white70,
                              thumbColor: Colors.white,
                              inactiveTrackColor: Colors.white24,
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 10,
                              ),
                              trackHeight: 2,
                            ),
                            child: Slider(
                              value: _effectiveVolume,
                              onChanged: (value) =>
                                  unawaited(_setVolume(value)),
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _pickSpeed,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          minimumSize: const Size(48, 36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                        ),
                        child: Text(
                          _speedLabel(_speed),
                          style: AppTypography.caption.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      _chromeIcon(
                        TDIcons.swap_left,
                        tooltip: l10n.playerSwitchSource,
                        onTap: _switchSource,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _chromeIcon(
    IconData icon, {
    required String tooltip,
    required VoidCallback onTap,
    double size = 22,
    bool flip = false,
  }) {
    final child = Icon(icon, size: size, color: Colors.white);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: flip ? Transform.flip(flipX: true, child: child) : child,
    );
  }

  Widget _buildBlocked(BuildContext context, String reason) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(TDIcons.error_circle, size: 40, color: Colors.white38),
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.l10n.playerUnavailable,
              style: AppTypography.title.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TDButton(
                  text: context.l10n.playerSwitchSource,
                  type: TDButtonType.outline,
                  theme: TDButtonTheme.light,
                  size: TDButtonSize.small,
                  onTap: _switchSource,
                ),
                const SizedBox(width: AppSpacing.md),
                TDButton(
                  text: context.l10n.retry,
                  theme: TDButtonTheme.light,
                  size: TDButtonSize.small,
                  onTap: () =>
                      _prepare(_current?.id ?? widget.args?.fileId ?? ''),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 倍速文案：1x / 1.5x / 1.25x。
  static String _speedLabel(double speed) {
    final text = speed == speed.roundToDouble()
        ? speed.toInt().toString()
        : speed.toString();
    return '${text}x';
  }

  static String _format(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return hours > 0
        ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
        : '${two(minutes)}:${two(seconds)}';
  }
}

/// 倍速选择弹层。
class _SpeedSheet extends StatelessWidget {
  const _SpeedSheet({required this.options, required this.current});

  final List<double> options;
  final double current;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              context.l10n.playerSpeed,
              style: AppTypography.title.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final option in options)
            ListTile(
              dense: true,
              title: Text(
                _MediaPlayerPageState._speedLabel(option),
                style: AppTypography.bodySmall.copyWith(
                  color: option == current ? colors.brand : colors.textPrimary,
                ),
              ),
              trailing: option == current
                  ? Icon(TDIcons.check, size: 18, color: colors.brand)
                  : null,
              onTap: () => Navigator.of(context).pop(option),
            ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

/// 手势浮层的类型。
enum _HudKind {
  /// 横向滑动定位进度。
  seek,

  /// 右半屏上下滑动调音量。
  volume,

  /// 左半屏上下滑动调亮度。
  brightness,
}

/// 手势浮层的内容。
///
/// 只有瞬时反馈，因此不做持久化；[kind] 决定展示哪一种读数：
/// 音量 / 亮度展示百分比与进度条，定位展示目标时间与总时长。
final class _HudInfo {
  /// 定位浮层：目标时间 / 总时长 / 本次进退量（双击时有值，滑动时为 0）。
  const _HudInfo.seek({
    required this.position,
    required this.duration,
    required this.delta,
  }) : kind = _HudKind.seek,
       level = 0;

  /// 音量 / 亮度浮层：`level` 为 0 ~ 1 的展示比例。
  const _HudInfo.level({required this.kind, required this.level})
    : position = Duration.zero,
      duration = Duration.zero,
      delta = Duration.zero;

  /// 浮层类型。
  final _HudKind kind;

  /// 音量 / 亮度的展示比例（0 ~ 1）。
  final double level;

  /// 定位目标位置。
  final Duration position;

  /// 视频总时长。
  final Duration duration;

  /// 双击的进退量（正为前进）。
  final Duration delta;
}

/// 播放源选择弹层。
///
/// 一部影视可能存在多个视频文件（分集 / 分段 / 多目录），这里把**全部**来源
/// 都展示出来（含不可用项，标注原因），当前播放的那条高亮并给出勾选标记。
class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.files, required this.currentId});

  final List<MediaFile> files;
  final String? currentId;

  /// 副标题：分集 / 片段 · 分辨率 · 大小 · 来源。
  String _subtitle(MediaFile file) {
    final parts = <String>[
      if (file.episodeIndex != null) 'EP${file.episodeIndex}',
      if (file.partIndex != null && file.partIndex! > 1) '片段 ${file.partIndex}',
      if (file.resolution != null && file.resolution!.isNotEmpty)
        file.resolution!,
      if (file.size != null) formatFileSize(file.size!),
      if (file.source != null && file.source!.isNotEmpty) file.source!,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Text(
                  l10n.playerSwitchSource,
                  style: AppTypography.title.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${files.length}',
                  style: AppTypography.caption.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final selected = file.id == currentId;
                final subtitle = _subtitle(file);
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: colors.brandSubtle,
                  title: Text(
                    file.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: selected ? colors.brand : colors.textPrimary,
                    ),
                  ),
                  subtitle: subtitle.isEmpty
                      ? null
                      : Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                  trailing: !file.available
                      ? Text(
                          l10n.mediaFileUnavailable,
                          style: AppTypography.caption.copyWith(
                            color: colors.warning,
                          ),
                        )
                      : selected
                      ? Icon(TDIcons.check, size: 18, color: colors.brand)
                      : null,
                  enabled: file.available,
                  onTap: () => Navigator.of(context).pop(file.id),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

/// 文件大小展示（B / KB / MB / GB）。
String formatFileSize(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}
