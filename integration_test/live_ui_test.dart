import 'dart:io';

import 'package:ammds_client/app/app.dart';
import 'package:ammds_client/app/app_container.dart';
import 'package:ammds_client/core/constants/discovery_constants.dart';
import 'package:ammds_client/core/discovery/discovery_service.dart';
import 'package:ammds_client/core/discovery/discovery_transport.dart';
import 'package:ammds_client/core/l10n/l10n.dart';
import 'package:ammds_client/core/storage/storage_impl.dart';
import 'package:ammds_client/features/auth/presentation/pages/login_page.dart';
import 'package:ammds_client/features/home/presentation/pages/main_shell.dart';
import 'package:ammds_client/shared/widgets/app_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../test_support/test_app.dart';

/// 真实服务端 UI 端到端测试（客户端 App + 真实 AMMDS 服务端）。
///
/// 前置条件：一台运行中的 AMMDS 服务端，且库中存在小说与漫画数据。
/// 默认 `127.0.0.1:18099`（`ammds/ammds-e2e-pass`），
/// 可用 `AMMDS_E2E_HOST` / `AMMDS_E2E_PORT` / `AMMDS_E2E_USER` /
/// `AMMDS_E2E_PASS` 覆盖；服务端不可达或库中无数据时用例自动跳过。
///
/// 覆盖链路（全部走真实网络与真实服务端）：
///
/// ```text
/// 启动 → 登录（真实 Client API）→ 主界面
///   → 小说列表 → 详情 → 小说阅读器（服务端章节正文）
///   → 漫画列表 → 详情 → 漫画阅读器（服务端章节图片，图片真实加载）
/// ```
void main() {
  final host = Platform.environment['AMMDS_E2E_HOST'] ?? '127.0.0.1';
  final port =
      int.tryParse(Platform.environment['AMMDS_E2E_PORT'] ?? '') ?? 18099;
  final username = Platform.environment['AMMDS_E2E_USER'] ?? 'ammds';
  final password = Platform.environment['AMMDS_E2E_PASS'] ?? 'ammds-e2e-pass';

  late bool backendReachable;
  late Directory storageDirectory;

  setUpAll(() async {
    backendReachable = await _isReachable(host, port);
    if (!backendReachable) {
      // ignore: avoid_print
      print('[live-ui] 后端 http://$host:$port 不可达，UI 联调用例将跳过');
    }
  });

  setUp(() async {
    storageDirectory = await Directory.systemTemp.createTemp('ammds_live_ui');
  });

  tearDown(() async {
    if (storageDirectory.existsSync()) {
      await storageDirectory.delete(recursive: true);
    }
  });

  Widget buildApp() => ProviderScope(
    overrides: <Override>[
      preferencesStorageProvider.overrideWithValue(
        FilePreferencesStorage(
          file: File(
            '${storageDirectory.path}${Platform.pathSeparator}prefs.json',
          ),
        ),
      ),
      secureStorageProvider.overrideWithValue(
        FileSecureStorage(
          file: File(
            '${storageDirectory.path}${Platform.pathSeparator}secure.bin',
          ),
        ),
      ),
      discoveryTransportProvider.overrideWithValue(
        UdpDiscoveryTransport(
          additionalProbeTargets: <String>[
            DiscoveryConstants.loopbackProbeAddress,
            host,
          ],
        ),
      ),
      discoveryTuningProvider.overrideWithValue(
        const DiscoveryTuning(
          probeTimeout: Duration(milliseconds: 200),
          probeInterval: Duration(milliseconds: 150),
          probeRounds: 3,
        ),
      ),
    ],
    child: const AmmdsClientApp(),
  );

  /// 登录进入主界面。
  Future<AppLocalizations> login(WidgetTester tester) async {
    final loginReached = await waitReal(
      tester,
      () => find.byType(LoginPage).evaluate().isNotEmpty,
      maxRounds: 300,
      step: const Duration(milliseconds: 40),
    );
    expect(loginReached, isTrue, reason: '启动后应进入登录页');
    final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)));

    await tester.enterText(find.byType(TextField).at(0), 'http://$host:$port');
    await tester.enterText(find.byType(TextField).at(1), username);
    await tester.enterText(find.byType(TextField).at(2), password);
    await settle(tester, frames: 3);
    final button = find.widgetWithText(TDButton, l10n.loginButton);
    await tester.ensureVisible(button);
    await settle(tester, frames: 3);
    await tester.tap(button);

    final mainReached = await waitReal(
      tester,
      () => find.byType(MainShell).evaluate().isNotEmpty,
      maxRounds: 300,
      step: const Duration(milliseconds: 40),
    );
    if (!mainReached) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      expect(mainReached, isTrue, reason: '登录后应进入主界面: texts=$texts');
    }
    await settle(tester, frames: 6);
    return l10n;
  }

  /// 等待首个内容卡片出现（列表加载完成）。
  Future<bool> waitFirstCard(WidgetTester tester) => waitReal(
    tester,
    () => find.byType(ContentCard).evaluate().isNotEmpty,
    maxRounds: 300,
    step: const Duration(milliseconds: 40),
  );

  testWidgets('真实服务端：小说详情 → 小说阅读器（真实章节正文）', (tester) async {
    if (!backendReachable) {
      return;
    }
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    final l10n = await login(tester);

    // 切到小说模块
    await tester.tap(find.text(l10n.navNovel));
    await settle(tester, frames: 6);
    final listed = await waitFirstCard(tester);
    if (!listed) {
      // ignore: avoid_print
      print('[live-ui] 服务端小说库为空，跳过小说阅读器 UI 链路');
      await drainTimers(tester);
      return;
    }

    // 打开详情
    await tester.tap(find.byType(ContentCard).first);
    await settle(tester, frames: 6);
    final detailLoaded = await waitReal(
      tester,
      () => find.text(l10n.novelDetailTitle).evaluate().isNotEmpty,
      maxRounds: 300,
      step: const Duration(milliseconds: 40),
    );
    expect(detailLoaded, isTrue, reason: '应打开小说详情页');
    expect(find.text(l10n.chapterList), findsOneWidget, reason: '详情页应展示章节目录');

    // 打开第一章
    final chapterCell = find.byType(TDCell).first;
    await tester.ensureVisible(chapterCell);
    await settle(tester, frames: 3);
    await tester.tap(chapterCell);

    final readerOpened = await waitReal(
      tester,
      () => find.textContaining('/ ').evaluate().isNotEmpty &&
          find.byType(Scaffold).evaluate().length >= 2,
      maxRounds: 300,
      step: const Duration(milliseconds: 40),
    );
    expect(readerOpened, isTrue, reason: '应打开小说阅读器');

    // 阅读器应展示服务端正文（正文文本非空且包含正文占位内容）
    final reachedReader = await waitReal(
      tester,
      () => tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .any((text) => text.contains('正文')),
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    final bodyTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .where((text) => text.contains('正文'))
        .toList();
    if (!reachedReader) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      // ignore: avoid_print
      print('[live-ui] 阅读器文本诊断: $texts');
    }
    expect(
      bodyTexts,
      isNotEmpty,
      reason: '阅读器应渲染服务端返回的章节正文',
    );
    // 「上一章 / 下一章」入口存在
    expect(
      find.widgetWithText(TDButton, l10n.readerNextChapter),
      findsWidgets,
      reason: '阅读器应提供章节切换',
    );

    // 返回详情页
    final context = tester.element(find.byType(Scaffold).last);
    GoRouter.of(context).pop();
    await settle(tester, frames: 8);
    expect(find.text(l10n.chapterList), findsOneWidget);

    await drainTimers(tester);
  });

  testWidgets('真实服务端：漫画详情 → 漫画阅读器（真实章节图片）', (tester) async {
    if (!backendReachable) {
      return;
    }
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    final l10n = await login(tester);

    await tester.tap(find.text(l10n.navComic));
    await settle(tester, frames: 6);
    final listed = await waitFirstCard(tester);
    if (!listed) {
      // ignore: avoid_print
      print('[live-ui] 服务端漫画库为空，跳过漫画阅读器 UI 链路');
      await drainTimers(tester);
      return;
    }

    await tester.tap(find.byType(ContentCard).first);
    await settle(tester, frames: 6);
    final detailLoaded = await waitReal(
      tester,
      () => find.text(l10n.comicDetailTitle).evaluate().isNotEmpty,
      maxRounds: 300,
      step: const Duration(milliseconds: 40),
    );
    expect(detailLoaded, isTrue, reason: '应打开漫画详情页');

    final chapterCell = find.byType(TDCell).first;
    await tester.ensureVisible(chapterCell);
    await settle(tester, frames: 3);
    await tester.tap(chapterCell);

    // 阅读器应加载到真实图片（页数指示器出现）
    final readerOpened = await waitReal(
      tester,
      () => find.byType(PageView).evaluate().isNotEmpty,
      maxRounds: 300,
      step: const Duration(milliseconds: 40),
    );
    expect(readerOpened, isTrue, reason: '应打开漫画阅读器');

    // 等待图片从服务端加载完成：错误占位图标不应出现
    await waitReal(
      tester,
      () =>
          find.byType(Image).evaluate().isNotEmpty &&
          find.byIcon(TDIcons.image_error).evaluate().isEmpty,
      maxRounds: 150,
      step: const Duration(milliseconds: 40),
    );
    expect(
      find.byIcon(TDIcons.image_error),
      findsNothing,
      reason: '章节图片应能从服务端正常加载（未出现加载失败占位）',
    );

    // 连续滚动模式可切换
    await tester.tap(find.byIcon(TDIcons.menu));
    await settle(tester, frames: 10);
    expect(find.byType(PageView), findsNothing, reason: '连续模式应改为纵向长图列表');

    await drainTimers(tester);
  });
}

/// 探测后端是否在线。
Future<bool> _isReachable(String host, int port) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final request = await client.getUrl(
      Uri.parse('http://$host:$port/api/client/v1/health'),
    );
    final response = await request.close();
    await response.drain<void>();
    client.close();
    return response.statusCode == 200;
  } on Object {
    return false;
  }
}
