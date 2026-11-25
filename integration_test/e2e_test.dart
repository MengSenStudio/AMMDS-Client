import 'dart:convert';
import 'dart:io';

import 'package:ammds_client/app/app.dart';
import 'package:ammds_client/app/app_container.dart';
import 'package:ammds_client/core/constants/discovery_constants.dart';
import 'package:ammds_client/core/discovery/discovery_service.dart';
import 'package:ammds_client/core/discovery/discovery_transport.dart';
import 'package:ammds_client/core/l10n/l10n.dart';
import 'package:ammds_client/core/storage/storage_impl.dart';
import 'package:ammds_client/domain/entities/content.dart';
import 'package:ammds_client/domain/entities/promote.dart';
import 'package:ammds_client/domain/entities/reading.dart';
import 'package:ammds_client/domain/repositories/repositories.dart';
import 'package:ammds_client/features/auth/presentation/pages/login_page.dart';
import 'package:ammds_client/features/home/presentation/pages/main_shell.dart';
import 'package:ammds_client/features/management/presentation/pages/management_page.dart';
import 'package:ammds_client/features/splash/presentation/pages/splash_page.dart';
import 'package:ammds_client/shared/widgets/account_avatar_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../test_support/mock_ammds_server.dart';
import '../test_support/test_app.dart';

/// 读取「服务端地址」输入框的当前文本（地址是输入框内容，不是 `Text` 组件）。
String addressFieldText(WidgetTester tester) {
  final field = tester.widget<TextField>(find.byType(TextField).at(0));
  return field.controller?.text ?? '';
}

/// 确保阅读器操作栏可见。
///
/// 阅读器（小说 / 漫画）的操作栏会在展示一段时间后**自动隐藏**并进入沉浸式全屏
/// （文档 #8），因此用例在点击导航栏 / 底栏控件之前必须先把它调出来；
/// 已可见时不做任何事，避免把操作栏又切换回隐藏状态。
Future<void> ensureReaderChrome(WidgetTester tester) async {
  if (find.byType(TDNavBar).evaluate().isNotEmpty) {
    return;
  }
  await tester.tapAt(tester.getCenter(find.byType(Scaffold).last));
  await settle(tester, frames: 6);
}

/// 端到端测试（文档 #79.3 / #80 / 「功能验证」）。
///
/// 覆盖链路：
///
/// ```text
/// 启动 → UDP 发现服务端 → 选择服务端 → 登录（RSA 加密密码）
///   → 进入主界面 → 加载内容列表 → 打开详情 → 退出登录
/// ```
///
/// 与单元/组件测试不同，这里使用**真实 UDP socket** 与**真实 HTTP 服务端**，
/// 只有「本地存储目录」被指向临时目录，以避免污染开发者环境。
void main() {
  late MockAmmdsServer server;
  late Directory storageDirectory;

  setUp(() async {
    server = MockAmmdsServer(requirePasswordEncryption: true);
    await server.start();
    storageDirectory = await Directory.systemTemp.createTemp('ammds_e2e');
  });

  tearDown(() async {
    await server.stop();
    if (storageDirectory.existsSync()) {
      await storageDirectory.delete(recursive: true);
    }
  });

  /// 组装真实环境的应用（真实 socket + 真实 Dio + 临时文件存储）。
  Widget buildApp() {
    return ProviderScope(
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
        // 真实 UDP 传输：额外把回环地址作为探测目标，
        // 保证单机环境下也能走完整的「发包 → 收包 → 解码」链路。
        discoveryTransportProvider.overrideWithValue(
          UdpDiscoveryTransport(
            additionalProbeTargets: const <String>[
              DiscoveryConstants.loopbackProbeAddress,
            ],
          ),
        ),
        discoveryTuningProvider.overrideWithValue(
          const DiscoveryTuning(
            probeTimeout: Duration(milliseconds: 150),
            probeInterval: Duration(milliseconds: 120),
            probeRounds: 3,
          ),
        ),
        // 官方推送通告走的是**公网**静态 JSON（不经 AMMDS 服务端），
        // 真实网络下会在进入主界面后弹出模态框，遮挡后续交互步骤。
        // 端到端测试只针对本地桩服务端，这里把它替换为「永不推送」，
        // 保证用例不受外部网络与弹窗时序影响（推送本身由单元 / 组件测试覆盖）。
        promoteRepositoryProvider.overrideWithValue(const _NoPromoteRepository()),
      ],
      child: const AmmdsClientApp(),
    );
  }

  /// 完成「发现 → 登录 → 主界面」流程，返回中文本地化文案。
  Future<AppLocalizations> loginToMain(
    WidgetTester tester,
    MockAmmdsServer server,
  ) async {
    final loginReached = await waitReal(
      tester,
      () => find.byType(LoginPage).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(loginReached, isTrue, reason: '启动后应进入登录页');
    final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)));
    await waitReal(
      tester,
      () => find.text(l10n.discovering).evaluate().isEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'http://127.0.0.1:${server.port}',
    );
    await tester.enterText(find.byType(TextField).at(1), server.username);
    await tester.enterText(find.byType(TextField).at(2), server.password);
    await settle(tester, frames: 3);
    final loginButton = find.widgetWithText(TDButton, l10n.loginButton);
    await tester.ensureVisible(loginButton);
    await settle(tester, frames: 3);
    await tester.tap(loginButton);
    final mainReached = await waitReal(
      tester,
      () => find.byType(MainShell).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(mainReached, isTrue, reason: '登录后应进入主界面');
    await settle(tester, frames: 6);
    return l10n;
  }

  testWidgets('端到端：发现 → 登录 → 主界面 → 详情 → 退出', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp());
    await tester.pump();

    // 1) 开屏
    expect(find.byType(SplashPage), findsOneWidget);

    // 2) 启动完成 → 登录页（真实 UDP 发现）
    final loginReached = await waitReal(
      tester,
      () => find.byType(LoginPage).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(loginReached, isTrue, reason: '启动后应进入登录页');

    final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)));

    // 发现需要真实网络收发：「正在搜索」状态消失即代表已发现服务端。
    final discovered = await waitReal(
      tester,
      () => find.text(l10n.discovering).evaluate().isEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(
      discovered,
      isTrue,
      reason: 'UDP 发现应找到服务端（已发送 ${server.discoveryProbes} 次探测）',
    );
    // 发现结果会自动预填到地址输入框。
    // 真实 UDP 下 host 取自**报文来源网卡**（可能是回环，也可能是局域网地址），
    // 因此只断言「已预填」且端口与测试桩一致，不依赖具体网卡地址。
    final prefilled = await waitReal(
      tester,
      () {
        final text = addressFieldText(tester);
        return text.startsWith('http://') && text.endsWith(':${server.port}');
      },
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(
      prefilled,
      isTrue,
      reason:
          '发现结果应自动预填到地址输入框（端口应为 ${server.port}），'
          '实际为「${addressFieldText(tester)}」',
    );

    // 3) 填写服务端地址与凭据
    // 表单顺序为「服务端地址 / 账户 / 密码」；地址显式填写以保证端口与测试桩一致。
    await tester.enterText(
      find.byType(TextField).at(0),
      'http://127.0.0.1:${server.port}',
    );
    await tester.enterText(find.byType(TextField).at(1), server.username);
    await tester.enterText(find.byType(TextField).at(2), server.password);
    await settle(tester, frames: 3);
    final loginButton = find.widgetWithText(TDButton, l10n.loginButton);
    await tester.ensureVisible(loginButton);
    await settle(tester, frames: 3);
    await tester.tap(loginButton);

    final mainReached = await waitReal(
      tester,
      () => find.byType(MainShell).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    if (!mainReached) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      expect(
        mainReached,
        isTrue,
        reason:
            '登录诊断 attempts=${server.loginAttempts} '
            'failures=${server.loginFailures} '
            'encrypted=${server.encryptedLoginAttempts} texts=$texts',
      );
    }
    expect(server.loginAttempts, 1);
    expect(server.encryptedLoginAttempts, 1, reason: '客户端应使用服务端公钥加密密码后再登录');

    // 4) 主界面加载影视列表
    final listLoaded = await waitReal(
      tester,
      () => find.text('Movie 1').evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(listLoaded, isTrue, reason: '主界面应加载影视列表');

    // 5) 打开详情
    await tester.tap(find.text('Movie 1'));
    // 详情页包含一次异步请求，等待「简介」区块出现即为加载完成。
    final detailLoaded = await waitReal(
      tester,
      () =>
          find.text(l10n.mediaDetailTitle).evaluate().isNotEmpty &&
          find.text(l10n.overview).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    if (!detailLoaded) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      expect(detailLoaded, isTrue, reason: '应能打开影视详情页: texts=$texts');
    }
    expect(find.text(l10n.overview), findsWidgets);

    // 返回主界面（详情页使用 TDNavBar，返回动作由路由承担）。
    final detailContext = tester.element(find.text(l10n.overview).first);
    GoRouter.of(detailContext).pop();
    await settle(tester, frames: 6);
    expect(find.byType(MainShell), findsOneWidget);

    // 6) 退出登录（管理页由右上角账号头像进入）
    await tester.tap(find.byType(AccountAvatarButton).last);
    await settle(tester, frames: 6);
    expect(find.byType(ManagementPage), findsOneWidget);

    final logoutCell = find.text(l10n.logout);
    await tester.ensureVisible(logoutCell);
    await settle(tester, frames: 3);
    await tester.tap(logoutCell);
    await settle(tester, frames: 6);
    await tester.tap(find.text(l10n.confirm));

    final backToLogin = await waitReal(
      tester,
      () => find.byType(LoginPage).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(backToLogin, isTrue, reason: '退出登录后应回到登录页');

    // 7) 本地认证信息已被清理
    final secureFile = File(
      '${storageDirectory.path}${Platform.pathSeparator}secure.bin',
    );
    expect(secureFile.existsSync(), isTrue);
    expect(await secureFile.readAsString(), isNot(contains('access-')));

    await drainTimers(tester);
  });

  testWidgets('端到端：小说详情 → 小说阅读器 → 章节切换', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    final l10n = await loginToMain(tester, server);

    // 切到小说模块并打开详情
    await tester.tap(find.text(l10n.navNovel));
    await settle(tester, frames: 6);
    final novelListed = await waitReal(
      tester,
      () => find.text('Novel 1').evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(novelListed, isTrue, reason: '小说列表应加载完成');

    await tester.tap(find.text('Novel 1'));
    await settle(tester, frames: 6);
    final detailLoaded = await waitReal(
      tester,
      () => find.text(l10n.novelDetailTitle).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(detailLoaded, isTrue, reason: '应打开小说详情页');
    expect(find.text('第 1 章'), findsWidgets, reason: '详情页应展示服务端章节目录');
    expect(find.text(l10n.detailSectionInfo), findsOneWidget, reason: '详情页应展示扩展属性');

    // 打开阅读器（点击第二章）
    await tester.tap(find.text('第 2 章').first);
    await settle(tester, frames: 6);
    final readerOpened = await waitReal(
      tester,
      // 阅读器默认「翻页」模式：正文按段落分页渲染，每段一个 Text 且首行带缩进前缀，
      // 因此这里按段落内容匹配而不是整章字符串。
      () => find.textContaining('第 2 章正文第一段').evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    if (!readerOpened) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      expect(readerOpened, isTrue, reason: '阅读器应加载章节正文: texts=$texts');
    }
    expect(find.text(l10n.readerChapterProgress(2, 3)), findsOneWidget);

    // 上一章（操作栏可能已自动隐藏，先调出来）
    await ensureReaderChrome(tester);
    await tester.tap(
      find.widgetWithText(TDButton, l10n.readerPrevChapter).last,
    );
    final prevLoaded = await waitReal(
      tester,
      () => find.textContaining('第 1 章正文第一段').evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(prevLoaded, isTrue, reason: '应能切换到上一章');
    expect(find.text(l10n.readerChapterProgress(1, 3)), findsOneWidget);

    // 返回详情页
    final readerContext = tester.element(find.byType(Scaffold).last);
    GoRouter.of(readerContext).pop();
    await settle(tester, frames: 6);
    final backToDetail = await waitReal(
      tester,
      () => find.text(l10n.detailSectionInfo).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(backToDetail, isTrue, reason: '应返回小说详情页');

    await drainTimers(tester);
  });

  testWidgets('端到端：漫画详情 → 漫画阅读器（翻页 / 连续模式 / 章节切换）', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    final l10n = await loginToMain(tester, server);

    // 切到漫画模块并打开详情
    await tester.tap(find.text(l10n.navComic));
    await settle(tester, frames: 6);
    final comicListed = await waitReal(
      tester,
      () => find.text('Comic 1').evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(comicListed, isTrue, reason: '漫画列表应加载完成');

    await tester.tap(find.text('Comic 1'));
    await settle(tester, frames: 6);
    final detailLoaded = await waitReal(
      tester,
      () => find.text(l10n.comicDetailTitle).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(detailLoaded, isTrue, reason: '应打开漫画详情页');

    // 打开阅读器
    await tester.tap(find.text('第 1 章').first);
    await settle(tester, frames: 6);
    final readerOpened = await waitReal(
      tester,
      () => find.text(l10n.comicPageProgress(1, 2)).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    if (!readerOpened) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      expect(readerOpened, isTrue, reason: '漫画阅读器应加载章节图片: texts=$texts');
    }
    // 章节加载完成后应出现 2 张图片
    await waitReal(
      tester,
      () => find.byType(Image).evaluate().length >= 2,
      maxRounds: 60,
      step: const Duration(milliseconds: 40),
    );

    // 翻到下一页（PageView 需要带速度的滑动才会翻页）
    final pageView = find.byType(PageView);
    expect(pageView, findsOneWidget);
    await tester.fling(pageView, const Offset(-600, 0), 1200);
    // 直接断言翻页结果（页码文本位于底栏，而底栏会随沉浸式自动隐藏，
    // 因此不用它作为判据，避免用例与自动隐藏时机耦合）。
    final nextPage = await waitReal(
      tester,
      () {
        final controller = tester
            .widget<PageView>(find.byType(PageView))
            .controller;
        return (controller?.page ?? 0) >= 1;
      },
      maxRounds: 60,
      step: const Duration(milliseconds: 40),
    );
    expect(nextPage, isTrue, reason: '应能翻到第二章图片');

    // 切换为连续滚动模式（操作栏可能已自动隐藏，先调出来）
    await ensureReaderChrome(tester);
    await tester.tap(find.byIcon(TDIcons.menu));
    await settle(tester, frames: 10);
    expect(find.byType(PageView), findsNothing, reason: '连续模式应改为纵向长图列表');

    // 下一话
    await ensureReaderChrome(tester);
    await tester.tap(
      find.widgetWithText(TDButton, l10n.readerNextChapter).last,
    );
    final nextLoaded = await waitReal(
      tester,
      () => find.text(l10n.comicPageProgress(1, 2)).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(nextLoaded, isTrue, reason: '应能切换到下一话');

    await drainTimers(tester);
  });

  testWidgets('端到端：会话在重启后自动恢复（真实存储 + 真实服务端）', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 第一次启动：登录并写入真实存储。
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await waitReal(
      tester,
      () => find.byType(LoginPage).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)));
    await waitReal(
      tester,
      () => find.text(l10n.discovering).evaluate().isEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'http://127.0.0.1:${server.port}',
    );
    await tester.enterText(find.byType(TextField).at(1), server.username);
    await tester.enterText(find.byType(TextField).at(2), server.password);
    await settle(tester, frames: 3);
    final loginButton = find.widgetWithText(TDButton, l10n.loginButton);
    await tester.ensureVisible(loginButton);
    await settle(tester, frames: 3);
    await tester.tap(loginButton);
    await waitReal(
      tester,
      () => find.byType(MainShell).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(find.byType(MainShell), findsOneWidget);

    // 第二次启动：模拟进程重启（新的 ProviderScope，复用同一份本地存储）。
    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey<String>('restart'),
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
              additionalProbeTargets: const <String>[
                DiscoveryConstants.loopbackProbeAddress,
              ],
            ),
          ),
          discoveryTuningProvider.overrideWithValue(
            const DiscoveryTuning(
              probeTimeout: Duration(milliseconds: 150),
              probeInterval: Duration(milliseconds: 120),
              probeRounds: 3,
            ),
          ),
          promoteRepositoryProvider.overrideWithValue(
            const _NoPromoteRepository(),
          ),
        ],
        child: const AmmdsClientApp(),
      ),
    );
    await tester.pump();

    final restored = await waitReal(
      tester,
      () => find.byType(MainShell).evaluate().isNotEmpty,
      maxRounds: 300,
      step: const Duration(milliseconds: 40),
    );
    if (!restored) {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LoginPage)),
        listen: false,
      );
      final bootstrap = container.read(bootstrapManagerProvider).state;
      final manager = container.read(serverManagerProvider);
      final storedActiveId = await container
          .read(settingsRepositoryProvider)
          .readActiveServerId();
      final storedSession = await container.read(sessionStoreProvider).read();
      final profiles = manager.profiles
          .map((profile) => '${profile.id}@${profile.displayAddress}')
          .join(', ');
      expect(
        restored,
        isTrue,
        reason:
            '重启后应依据本地会话直接进入主界面: '
            'stage=${bootstrap.stage} dest=${bootstrap.destination} '
            'error=${bootstrap.error} conn=${manager.connectionState} '
            'active=${manager.activeServer?.id} storedActive=$storedActiveId '
            'profiles=[$profiles] hasSession=${storedSession != null}',
      );
    }
    expect(find.byType(LoginPage), findsNothing);

    await drainTimers(tester);
  });

  testWidgets('端到端：密码错误时给出登录失败提示且不进入主界面', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    final loginReached = await waitReal(
      tester,
      () => find.byType(LoginPage).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(loginReached, isTrue);
    final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)));
    await waitReal(
      tester,
      () => find.text(l10n.discovering).evaluate().isEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );

    await tester.enterText(
      find.byType(TextField).at(0),
      'http://127.0.0.1:${server.port}',
    );
    await tester.enterText(find.byType(TextField).at(1), server.username);
    await tester.enterText(find.byType(TextField).at(2), 'wrong-password');
    await settle(tester, frames: 3);
    final loginButton = find.widgetWithText(TDButton, l10n.loginButton);
    await tester.ensureVisible(loginButton);
    await settle(tester, frames: 3);
    await tester.tap(loginButton);
    await waitReal(tester, () => false, maxRounds: 60);

    expect(find.byType(MainShell), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(server.loginFailures, greaterThanOrEqualTo(1));

    await drainTimers(tester);
  });

  testWidgets('端到端：阅读进度同步到服务端并可跨设备续读', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 设备 A：登录 → 写入阅读进度（应同步到服务端）
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await waitReal(
      tester,
      () => find.byType(LoginPage).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)));
    await waitReal(
      tester,
      () => find.text(l10n.discovering).evaluate().isEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'http://127.0.0.1:${server.port}',
    );
    await tester.enterText(find.byType(TextField).at(1), server.username);
    await tester.enterText(find.byType(TextField).at(2), server.password);
    await settle(tester, frames: 3);
    final loginButton = find.widgetWithText(TDButton, l10n.loginButton);
    await tester.ensureVisible(loginButton);
    await settle(tester, frames: 3);
    await tester.tap(loginButton);
    final loggedIn = await waitReal(
      tester,
      () => find.byType(MainShell).evaluate().isNotEmpty,
      maxRounds: 200,
      step: const Duration(milliseconds: 40),
    );
    expect(loggedIn, isTrue, reason: '登录后应进入主界面');

    final containerA = ProviderScope.containerOf(
      tester.element(find.byType(MainShell)),
      listen: false,
    );
    await containerA.read(readingRepositoryProvider).writeProgress(
      const ReadingProgress(
        kind: ContentKind.novel,
        id: 'novels-1',
        title: 'Novel 1',
        chapterId: 'chapter-2',
        chapterTitle: '第 2 章',
        chapterIndex: 2,
        page: 40,
      ),
    );

    // 同步是后台「尽力而为」，等待测试桩收到进度
    final synced = await waitReal(
      tester,
      () => server.savedReadProgress['novels:novels-1'] != null,
      maxRounds: 100,
      step: const Duration(milliseconds: 40),
    );
    expect(synced, isTrue, reason: '阅读进度应同步到服务端');
    final stored = server.savedReadProgress['novels:novels-1']!;
    expect(stored['chapter_id'], 'chapter-2');
    expect((stored['chapter_index'] as num).toInt(), 2);
    // 客户端用 0~100 百分数，服务端契约是 0~1 比例
    expect((stored['percent'] as num).toDouble(), closeTo(0.4, 0.0001));

    // 设备 B：同一份会话与服务端档案，但**没有本地阅读进度**
    final deviceB = await Directory.systemTemp.createTemp('ammds_e2e_b');
    addTearDown(() async {
      if (deviceB.existsSync()) {
        await deviceB.delete(recursive: true);
      }
    });
    await File(
      '${storageDirectory.path}${Platform.pathSeparator}secure.bin',
    ).copy('${deviceB.path}${Platform.pathSeparator}secure.bin');
    final prefsSource = File(
      '${storageDirectory.path}${Platform.pathSeparator}prefs.json',
    );
    final deviceBPrefs = File(
      '${deviceB.path}${Platform.pathSeparator}prefs.json',
    );
    final deviceAValues =
        jsonDecode(await prefsSource.readAsString()) as Map<Object?, Object?>;
    await deviceBPrefs.writeAsString(
      jsonEncode(<String, Object?>{
        for (final entry in deviceAValues.entries)
          // 保留服务端档案 / 会话相关配置，去掉阅读进度
          if ('${entry.key}' != 'reader.progress')
            '${entry.key}': entry.value,
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey<String>('device-b'),
        overrides: <Override>[
          preferencesStorageProvider.overrideWithValue(
            FilePreferencesStorage(file: deviceBPrefs),
          ),
          secureStorageProvider.overrideWithValue(
            FileSecureStorage(
              file: File('${deviceB.path}${Platform.pathSeparator}secure.bin'),
            ),
          ),
          discoveryTransportProvider.overrideWithValue(
            UdpDiscoveryTransport(
              additionalProbeTargets: const <String>[
                DiscoveryConstants.loopbackProbeAddress,
              ],
            ),
          ),
          discoveryTuningProvider.overrideWithValue(
            const DiscoveryTuning(
              probeTimeout: Duration(milliseconds: 150),
              probeInterval: Duration(milliseconds: 120),
              probeRounds: 3,
            ),
          ),
          promoteRepositoryProvider.overrideWithValue(
            const _NoPromoteRepository(),
          ),
        ],
        child: const AmmdsClientApp(),
      ),
    );
    await tester.pump();
    final restored = await waitReal(
      tester,
      () => find.byType(MainShell).evaluate().isNotEmpty,
      maxRounds: 300,
      step: const Duration(milliseconds: 40),
    );
    expect(restored, isTrue, reason: '设备 B 应依据会话直接进入主界面');

    final containerB = ProviderScope.containerOf(
      tester.element(find.byType(MainShell)),
      listen: false,
    );
    final progress = await containerB
        .read(readingRepositoryProvider)
        .readProgress(ContentKind.novel, 'novels-1');
    expect(progress, isNotNull, reason: '设备 B 本地为空，应从服务端续读');
    expect(progress!.chapterId, 'chapter-2');
    expect(progress.chapterIndex, 2);
    expect(progress.page, 40);

    await drainTimers(tester);
  });
}

/// 假官方推送仓库：端到端测试中永不推送。
///
/// 官方推送通告来自**公网**静态 JSON（不经 AMMDS 服务端），真实网络下
/// 会在进入主界面后弹出不可关闭的模态框，遮挡后续交互步骤。
final class _NoPromoteRepository implements PromoteRepository {
  const _NoPromoteRepository();

  @override
  Future<List<AppPromote>> load() async => const <AppPromote>[];

  @override
  Future<List<AppPromote>> pending({DateTime? now}) async =>
      const <AppPromote>[];

  @override
  Future<void> markRead(String id, {DateTime? now}) async {}
}
