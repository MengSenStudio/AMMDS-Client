import 'dart:async';

import 'package:ammds_client/app/app_container.dart';
import 'package:ammds_client/core/l10n/l10n.dart';
import 'package:ammds_client/core/storage/storage_impl_memory.dart';
import 'package:ammds_client/core/theme/app_theme.dart';
import 'package:ammds_client/domain/entities/content.dart';
import 'package:ammds_client/domain/repositories/repositories.dart';
import 'package:ammds_client/features/media/presentation/pages/media_player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../test_support/test_app.dart';

/// 播放页组件测试（手势与操作栏显隐）。
///
/// 播放引擎用假的 [VideoPlayerPlatform] 顶替：不需要网络与解码器，
/// 只验证「手势 → 播放器指令 / 界面反馈」这条链路。
void main() {
  /// 测试片源时长。
  const duration = Duration(minutes: 2);

  /// `screen_brightness` 的方法通道（见 screen_brightness_platform_interface）。
  const brightnessChannel = MethodChannel(
    'github.com/aaassseee/screen_brightness',
  );

  late _FakeVideoPlayerPlatform platform;
  late _FakeScreenBrightness brightness;

  setUp(() {
    platform = _FakeVideoPlayerPlatform(duration: duration);
    VideoPlayerPlatform.instance = platform;
    brightness = _FakeScreenBrightness();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(brightnessChannel, brightness.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(brightnessChannel, null);
  });

  /// 播放页所在的舞台区域（承载拖动与单击 / 双击判定的手势层）。
  final Finder stage = find.byWidgetPredicate(
    (widget) =>
        widget is GestureDetector &&
        widget.onHorizontalDragUpdate != null &&
        widget.onVerticalDragUpdate != null,
  );

  Future<AppLocalizations> pumpPlayer(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1600);
    addTearDown(tester.view.reset);
    TDTheme.needMultiTheme();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          contentRepositoryProvider.overrideWithValue(
            _FakePlaybackRepository(),
          ),
          preferencesStorageProvider.overrideWithValue(
            InMemoryPreferencesStorage(),
          ),
          secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: TDTheme(
            data: TDTheme.defaultData(),
            systemData: AppTheme.light(),
            child: const MediaPlayerPage(
              args: MediaPlayerArgs(
                title: '测试影片',
                files: <MediaFile>[_file],
                fileId: _fileId,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester, frames: 8);
    return AppLocalizations.of(tester.element(find.byType(Scaffold)));
  }

  /// 结束用例：卸载页面（触发释放），排空挂起的定时器。
  Future<void> disposePlayer(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await drainTimers(tester);
  }

  /// 单击画面（单击要等过双击判定窗口才生效）。
  Future<void> tapStage(WidgetTester tester, Offset position) async {
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 双击画面。
  Future<void> doubleTapStage(WidgetTester tester, Offset position) async {
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('单击画面：播放 / 暂停切换，并重新唤出操作栏', (tester) async {
    final l10n = await pumpPlayer(tester);
    final rect = tester.getRect(stage);
    expect(platform.playing, isTrue);
    expect(find.byTooltip(l10n.playerPause), findsOneWidget);

    // 单击暂停：按钮切为「播放」。
    // 注意 `tester.tapAt` 是「按下即松开」的瞬时点击，对应浏览器里
    // 不足 100ms 的鼠标单击——这种快速点击同样必须生效。
    await tapStage(tester, rect.center);
    expect(platform.playing, isFalse);
    expect(find.byTooltip(l10n.playerPlay), findsOneWidget);

    // 无操作 3 秒后操作栏自动收起（暂停也不例外）
    await settle(tester, frames: 40, step: const Duration(milliseconds: 100));
    expect(find.byTooltip(l10n.playerPlay), findsNothing);
    expect(find.textContaining(l10n.playerSourceCurrent), findsNothing);

    // 再单击：恢复播放并唤出操作栏
    await tapStage(tester, rect.center);
    expect(platform.playing, isTrue);
    expect(find.byTooltip(l10n.playerPause), findsOneWidget);
    expect(find.textContaining(l10n.playerSourceCurrent), findsOneWidget);

    await disposePlayer(tester);
  });

  testWidgets('双击左右半屏：后退 / 前进 10 秒并给出浮层', (tester) async {
    await pumpPlayer(tester);
    final rect = tester.getRect(stage);
    platform.position = const Duration(seconds: 30);
    await settle(tester, frames: 6, step: const Duration(milliseconds: 200));

    // 右半屏双击：前进 10 秒
    await doubleTapStage(tester, Offset(rect.right - 40, rect.center.dy));
    expect(platform.seekTarget, const Duration(seconds: 40));
    expect(find.text('+10s'), findsOneWidget);

    // 左半屏双击：后退 10 秒
    await doubleTapStage(tester, Offset(rect.left + 40, rect.center.dy));
    expect(platform.seekTarget, const Duration(seconds: 30));
    expect(find.text('-10s'), findsOneWidget);

    // 双击不应被同时判成单击（否则会顺带暂停）
    expect(platform.playing, isTrue);
    // 浮层自动消失
    await settle(tester, frames: 12, step: const Duration(milliseconds: 100));
    expect(find.text('-10s'), findsNothing);

    await disposePlayer(tester);
  });

  testWidgets('横向滑动：按满屏宽度换算定位进度', (tester) async {
    await pumpPlayer(tester);
    final rect = tester.getRect(stage);

    // 向右滑 180px（触屏拖动前 20px 用于越过分歧阈值）：
    // 约 160/900 × 120s ≈ 21.3s
    await tester.dragFrom(rect.center, const Offset(180, 0));
    await settle(tester, frames: 4);

    expect(platform.seekTarget, isNotNull);
    final seconds = platform.seekTarget!.inSeconds;
    expect(seconds, inInclusiveRange(20, 24));
    // 定位过程中操作栏保持可见
    expect(find.byType(Slider), findsWidgets);

    await disposePlayer(tester);
  });

  testWidgets('左半屏上下滑动：调整屏幕亮度并给出亮度浮层', (tester) async {
    final l10n = await pumpPlayer(tester);
    final rect = tester.getRect(stage);
    // 进入播放页只读取当前亮度，不下发设置
    expect(brightness.writes, isEmpty);

    // 向下滑动：亮度降低并下发给原生插件
    await tester.dragFrom(
      Offset(rect.left + 60, rect.center.dy),
      const Offset(0, 200),
    );
    await settle(tester, frames: 3);

    expect(brightness.writes, isNotEmpty);
    expect(brightness.writes.last, lessThan(brightness.current));
    expect(find.text(l10n.playerBrightness), findsOneWidget);
    // 亮度手势不改变音量
    expect(platform.volume, 1);

    // 向上滑动：亮度回升
    final dimmed = brightness.writes.last;
    await tester.dragFrom(
      Offset(rect.left + 60, rect.center.dy),
      const Offset(0, -400),
    );
    await settle(tester, frames: 3);

    expect(brightness.writes.last, greaterThan(dimmed));

    // 离开播放页：恢复进入前的亮度
    await disposePlayer(tester);
    expect(brightness.reset, isTrue);
  });

  testWidgets('右半屏上下滑动：调整音量并给出音量浮层', (tester) async {
    final l10n = await pumpPlayer(tester);
    final rect = tester.getRect(stage);

    // 向下滑动：音量降低
    await tester.dragFrom(
      Offset(rect.right - 60, rect.center.dy),
      const Offset(0, 200),
    );
    await settle(tester, frames: 3);

    expect(platform.volume, lessThan(1));
    expect(platform.volume, greaterThan(0.7));
    expect(find.text(l10n.playerVolume), findsOneWidget);
    // 音量手势不调整屏幕亮度
    expect(brightness.writes, isEmpty);

    // 继续向下滑到底：静音
    await tester.dragFrom(
      Offset(rect.right - 60, rect.center.dy),
      const Offset(0, 1200),
    );
    await settle(tester, frames: 3);

    expect(platform.volume, 0);
    expect(find.text('0%'), findsOneWidget);

    await disposePlayer(tester);
  });

  testWidgets('播放结束：操作栏同样按无操作自动收起', (tester) async {
    final l10n = await pumpPlayer(tester);
    platform.complete();
    await settle(tester, frames: 6);

    // 结束时先展示完成态，随后照常自动收起
    expect(platform.playing, isFalse);
    await settle(tester, frames: 40, step: const Duration(milliseconds: 100));
    expect(find.byTooltip(l10n.playerPlay), findsNothing);
    expect(find.textContaining(l10n.playerSourceCurrent), findsNothing);

    await disposePlayer(tester);
  });
}

/// 测试用片源。
const String _fileId = 'file-1';
const MediaFile _file = MediaFile(
  id: _fileId,
  name: '测试片源.mp4',
  size: 51235,
  resolution: '1920x1080',
  episodeIndex: 1,
  source: 'MANUAL',
);

/// 假播放决策仓库：只实现播放页用到的决策接口。
final class _FakePlaybackRepository implements ContentRepository {
  @override
  Future<PlaybackDecision> playbackDecision(String fileId) async =>
      PlaybackDecision(
        mode: PlaybackMode.direct,
        url: 'http://127.0.0.1:9/api/client/v1/media/files/$fileId/stream',
      );

  @override
  Future<PageResult<ContentItem>> list(
    ContentKind kind, {
    String? cursor,
    int pageSize = 20,
    String? keyword,
    String? category,
  }) async => PageResult.empty;

  @override
  Future<ContentDetail> detail(ContentKind kind, String id) async =>
      throw UnimplementedError();

  @override
  Future<List<ContentChapter>> chapters(ContentKind kind, String id) async =>
      const <ContentChapter>[];

  @override
  Future<ChapterContent> novelChapterContent(
    String bookId,
    String chapterId,
  ) async => throw UnimplementedError();

  @override
  Future<ComicChapterPages> comicChapterPages(
    String albumId,
    String chapterId,
  ) async => throw UnimplementedError();
}

/// 假亮度插件：不触碰真实屏幕亮度，只记录播放器下发的调用。
final class _FakeScreenBrightness {
  /// 进入播放页时读到的「当前亮度」。
  double current = 0.6;

  /// 写入过的亮度值。
  final List<double> writes = <double>[];

  /// 是否调用过「恢复进入前的亮度」。
  bool reset = false;

  /// 方法通道处理（与 `screen_brightness` 的方法名 / 参数一致）。
  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'getApplicationScreenBrightness':
        return current;
      case 'setApplicationScreenBrightness':
        final arguments = call.arguments! as Map<Object?, Object?>;
        writes.add((arguments['brightness']! as num).toDouble());
        return null;
      case 'resetApplicationScreenBrightness':
        reset = true;
        return null;
      default:
        return null;
    }
  }
}

/// 假播放平台：不落盘、不解码，只记录播放器下发的指令。
///
/// 事件流用「单订阅 `StreamController`」：初始化事件先入队，
/// 等 `VideoPlayerController` 订阅后立即消费，因此无需等待真实平台回调。
final class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform({required this.duration});

  /// 片源时长。
  final Duration duration;

  final Map<int, StreamController<VideoEvent>> _events =
      <int, StreamController<VideoEvent>>{};
  final Map<int, Duration> _positions = <int, Duration>{};

  /// 当前是否播放中。
  bool playing = false;

  /// 最近一次音量设置。
  double volume = 1;

  /// 最近一次定位目标（未定位过为 null）。
  Duration? seekTarget;

  int _nextPlayerId = 0;

  int get playerId => _nextPlayerId - 1;

  /// 播放位置（模拟播放器上报的进度）。
  set position(Duration value) => _positions[playerId] = value;

  /// 触发「播放结束」。
  void complete() {
    _positions[playerId] = duration;
    _events[playerId]?.add(VideoEvent(eventType: VideoEventType.completed));
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextPlayerId++;
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    _positions[id] = Duration.zero;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: duration,
        size: const Size(1280, 720),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    await _events[playerId]?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async => playing = true;

  @override
  Future<void> pause(int playerId) async => playing = false;

  @override
  Future<void> setVolume(int playerId, double value) async => volume = value;

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _positions[playerId] = position;
    seekTarget = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}
