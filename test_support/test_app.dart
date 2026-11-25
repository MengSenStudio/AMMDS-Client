import 'package:ammds_client/app/app.dart';
import 'package:ammds_client/app/app_container.dart';
import 'package:ammds_client/core/discovery/discovery_models.dart';
import 'package:ammds_client/core/discovery/discovery_service.dart';
import 'package:ammds_client/core/discovery/discovery_transport.dart';
import 'package:ammds_client/core/storage/storage_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_http_adapter.dart';

/// 测试应用装配。
///
/// 使用真实的应用代码（路由、主题、会话、管理器、网络层），
/// 只把「存储」与「发现传输」替换为内存实现，
/// HTTP 通过 [MockHttpAdapter] 注入，全程无真实网络。
final class TestAppHarness {
  /// 创建装配。
  TestAppHarness({
    this.adapter,
    List<DiscoveryResponse>? discoveryReplies,
    bool discoveryFails = false,
    Map<String, String> initialPreferences = const <String, String>{},
  }) : preferences = InMemoryPreferencesStorage(),
       secureStorage = InMemorySecureStorage(),
       discoveryTransport = FakeDiscoveryTransport(
         replies: discoveryReplies ?? const <DiscoveryResponse>[],
         throwOnSend: discoveryFails,
       ) {
    for (final entry in initialPreferences.entries) {
      preferences.writeString(entry.key, entry.value);
    }
  }

  /// 普通配置存储。
  final InMemoryPreferencesStorage preferences;

  /// 安全存储。
  final InMemorySecureStorage secureStorage;

  /// 发现传输。
  final FakeDiscoveryTransport discoveryTransport;

  /// HTTP 适配器。
  final MockHttpAdapter? adapter;

  /// 组装 [ProviderScope] 的覆盖项。
  List<Override> get overrides => <Override>[
    preferencesStorageProvider.overrideWithValue(preferences),
    secureStorageProvider.overrideWithValue(secureStorage),
    discoveryTransportProvider.overrideWithValue(discoveryTransport),
    // 测试中使用极短的探测节奏，避免等待真实探测窗口。
    discoveryTuningProvider.overrideWithValue(
      const DiscoveryTuning(
        probeTimeout: Duration(milliseconds: 20),
        probeInterval: Duration(milliseconds: 20),
        probeRounds: 1,
      ),
    ),
    httpAdapterProvider.overrideWithValue(adapter),
  ];

  /// 构建被测应用。
  Widget buildApp() =>
      ProviderScope(overrides: overrides, child: const AmmdsClientApp());
}

/// 反复 pump，直到条件满足或达到最大帧数。
///
/// 用于等待启动流程、异步加载等场景，避免依赖固定 pump 次数。
Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxFrames = 80,
  Duration step = const Duration(milliseconds: 50),
}) async {
  Object? failure;
  StackTrace? failureStack;
  for (var i = 0; i < maxFrames; i++) {
    if (condition()) {
      return true;
    }
    try {
      await tester.pump(step);
    } on Object catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
  }
  if (condition()) {
    return true;
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }
  return false;
}

/// 固定推进若干帧。
///
/// 应用内存在持续动画（Loading 指示器等），[WidgetTester.pumpAndSettle]
/// 可能永远不会结束，因此统一使用该辅助函数推进动画。
Future<void> settle(
  WidgetTester tester, {
  int frames = 36,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

/// 排空应用内所有短时定时器（Toast 自动消失、按钮回弹等）。
///
/// 测试结束时若仍有挂起的 Timer，Flutter 测试框架会直接判定失败，
/// 因此每个用例在结束前都应调用一次本函数。
Future<void> drainTimers(WidgetTester tester) =>
    settle(tester, frames: 40, step: const Duration(milliseconds: 100));

/// 在「虚拟时间 + 真实事件循环」之间交替推进，直到条件满足。
///
/// 应用同时存在两类异步：
/// * 由虚拟时钟驱动的 `Future.delayed`（启动流程、发现探测节奏）
/// * 真实事件循环驱动的网络与存储 IO（Dio、文件读写）
///
/// 因此每轮先 `pump(step)` 推进虚拟时间，再 `runAsync` 让真实 IO 前进；
/// 单独使用其中任意一种都会让另一类永久挂起。
///
/// [maxRounds] 是等待预算，默认 120 轮 × 50ms = 6s 虚拟时间，
/// 比官方开屏的最短展示时长（`AppMotion.splash`，3.6s）留出一倍余量，
/// 避免仅因开屏时长调整就让「等待进入登录页」类断言超时。
Future<bool> waitReal(
  WidgetTester tester,
  bool Function() condition, {
  int maxRounds = 120,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < maxRounds; i++) {
    if (condition()) {
      return true;
    }
    await tester.pump(step);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  return condition();
}
