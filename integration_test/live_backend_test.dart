import 'dart:io';

import 'package:ammds_client/core/constants/discovery_constants.dart';
import 'package:ammds_client/core/discovery/discovery_codec.dart';
import 'package:ammds_client/core/discovery/discovery_service.dart';
import 'package:ammds_client/core/discovery/discovery_transport.dart';
import 'package:ammds_client/core/errors/app_exception.dart';
import 'package:ammds_client/core/network/network_client.dart';
import 'package:ammds_client/data/api/ammds_public_api.dart';
import 'package:ammds_client/data/api/client_api.dart';
import 'package:ammds_client/data/api/server_api.dart';
import 'package:ammds_client/data/api/server_dialect.dart';
import 'package:ammds_client/data/repositories/repositories.dart';
import 'package:ammds_client/domain/entities/auth.dart';
import 'package:ammds_client/domain/entities/content.dart';
import 'package:ammds_client/domain/entities/server.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实后端联调测试。
///
/// 需要一台**实际运行中**的 AMMDS 服务端（默认 `127.0.0.1:18099`，
/// 可用 `AMMDS_E2E_HOST` / `AMMDS_E2E_PORT` / `AMMDS_E2E_USER` /
/// `AMMDS_E2E_PASS` 覆盖），且服务端已启用 UDP 发现（默认 47823 端口）。
///
/// 覆盖链路：
///
/// ```text
/// 真实 UDP 发现 → 接口方言探测（clientV1）→ 真实登录（RSA(明文)）
///   → 会话校验 → 用户信息 → 开屏配置 → 内容接口
/// ```
///
/// 服务端不可达时整组用例跳过，避免影响离线开发与 CI。
void main() {
  final host = Platform.environment['AMMDS_E2E_HOST'] ?? '127.0.0.1';
  final port =
      int.tryParse(Platform.environment['AMMDS_E2E_PORT'] ?? '') ?? 18099;
  final username = Platform.environment['AMMDS_E2E_USER'] ?? 'ammds';
  final password = Platform.environment['AMMDS_E2E_PASS'] ?? 'ammds-e2e-pass';

  late bool backendReachable;

  setUpAll(() async {
    backendReachable = await _isReachable(host, port);
    if (!backendReachable) {
      // ignore: avoid_print
      print('[live] 后端 http://$host:$port 不可达，真实联调用例将跳过');
    }
  });

  test('真实 UDP 发现能发现运行中的服务端', () async {
    if (!backendReachable) {
      return;
    }

    final service = DiscoveryService(
      transport: UdpDiscoveryTransport(additionalProbeTargets: <String>[host]),
      tuning: const DiscoveryTuning(
        probeTimeout: Duration(milliseconds: 200),
        probeInterval: Duration(milliseconds: 150),
        probeRounds: 3,
      ),
    );
    addTearDown(service.dispose);

    final outcome = await service.discover();

    expect(outcome.servers, isNotEmpty, reason: '应发现至少一个服务端');
    final discovered = outcome.servers.firstWhere(
      (server) => server.port == port,
      orElse: () => outcome.servers.first,
    );
    expect(discovered.port, port, reason: '发现结果应包含服务端真实端口');
    expect(discovered.apiVersion, isNotEmpty);
    expect(discovered.versionName, isNotNull, reason: '应上报服务端版本');
    expect(discovered.capabilities['media'], isTrue);
    expect(discovered.capabilities['novel'], isTrue);
    expect(DiscoveryConstants.port, 47823, reason: '发现端口约定');
    // ignore: avoid_print
    print(
      '[live] 发现服务端: ${discovered.name} @ ${discovered.displayAddress} '
      'version=${discovered.versionName} api=${discovered.apiVersion}',
    );
  });

  test('客户端可被动接收服务端周期广播（announce）', () async {
    if (!backendReachable) {
      return;
    }

    final transport = UdpDiscoveryTransport();
    addTearDown(transport.close);
    // 只绑定端口、**不主动探测**，单独验证「服务端广播 → 客户端被动接收」这一半链路。
    await transport.open(
      probePort: DiscoveryConstants.port,
      announcePort: DiscoveryConstants.announcePort,
    );
    expect(
      transport.receivesBroadcast,
      isTrue,
      reason: '应能绑定广播端口 ${DiscoveryConstants.announcePort}',
    );

    final datagram = await transport.responses
        .firstWhere((item) {
          try {
            return DiscoveryCodec.decodeResponse(
              item.bytes,
              sourceAddress: item.sourceAddress,
            ).isAnnounce;
          } on Object {
            return false;
          }
        })
        .timeout(const Duration(seconds: 25));

    final response = DiscoveryCodec.decodeResponse(
      datagram.bytes,
      sourceAddress: datagram.sourceAddress,
    );
    expect(response.type, DiscoveryConstants.typeAnnounce);
    expect(response.port, port);
    // ignore: avoid_print
    print(
      '[live] 收到周期广播: ${response.name} @ ${response.displayAddress} '
      '(type=${response.type})',
    );
  });

  test('方言探测选择 Client API 并可完成真实登录', () async {
    if (!backendReachable) {
      return;
    }

    final session = _LiveSession();
    addTearDown(session.close);

    final repository = ServerRepositoryImpl(
      apiFactory: session.apiFor,
      discoverer: ({
        void Function(ServerProfile server)? onServerFound,
      }) async => const <ServerProfile>[],
    );
    final candidate = ServerProfile(
      id: 'live-backend',
      name: 'Live AMMDS',
      host: host,
      port: port,
    );

    final probed = await repository.probe(candidate);
    expect(
      ServerDialect.fromProfile(probed),
      ServerDialect.clientV1,
      reason: '服务端已实现 /api/client/v1/**（health 探测优先命中）',
    );

    // 探测只负责判断连通性与方言；能力与版本需要读取 server/info。
    final info = await repository.fetchServerInfo(probed);
    expect(info.capabilities['media'], isTrue);
    expect(info.serverVersion, isNotEmpty);
    expect(info.apiVersion, 'v1');

    final api = session.apiForProfile(info);
    // 开屏配置属于免鉴权接口，应在登录前即可读取
    final splash = await api.fetchSplash();
    expect(splash.type, anyOf('official', 'ad'));

    final auth = AuthRepositoryImpl(apiFactory: session.apiForProfile);
    final result = await auth.login(
      server: info,
      credentials: AuthCredentials(username: username, password: password),
    );
    expect(result.tokens.accessToken, isNotEmpty);

    final valid = await auth.validateSession(
      server: info,
      accessToken: result.tokens.accessToken,
    );
    expect(valid, isTrue);

    final profile = await auth.fetchProfile(
      server: info,
      accessToken: result.tokens.accessToken,
    );
    expect(profile.username, username);
    // ignore: avoid_print
    print(
      '[live] 登录成功: ${profile.displayName} '
      '(dialect=${ServerDialect.fromProfile(info).code}, '
      'server=${info.serverVersion}, capabilities=${info.capabilities})',
    );

    // 内容接口应可达；空库时返回空列表而不是报错。
    // 应用内由 AuthInterceptor 注入令牌，联调装配需显式带上。
    session.accessToken = result.tokens.accessToken;
    final content = ContentRepositoryImpl(
      apiFactory: () => session.apiForProfile(info),
    );
    final media = await content.list(ContentKind.media, pageSize: 5);
    expect(media.items, isNotNull);
  });

  test('错误密码不会登录成功', () async {
    if (!backendReachable) {
      return;
    }

    final session = _LiveSession();
    addTearDown(session.close);
    final auth = AuthRepositoryImpl(apiFactory: session.apiForProfile);
    final server = ServerProfile(
      id: 'live-backend',
      name: 'Live AMMDS',
      host: host,
      port: port,
      dialect: ServerDialect.clientV1.code,
    );

    await expectLater(
      auth.login(
        server: server,
        credentials: AuthCredentials(
          username: username,
          password: 'definitely-wrong',
        ),
      ),
      throwsA(isA<AppException>()),
    );
  });

  test('真实后端：小说详情 → 章节正文（小说阅读器链路）', () async {
    if (!backendReachable) {
      return;
    }

    final live = await _LiveContent.open(
      host: host,
      port: port,
      username: username,
      password: password,
    );
    addTearDown(live.close);

    final novels = await live.content.list(ContentKind.novel, pageSize: 5);
    expect(novels.items, isNotNull);
    if (novels.items.isEmpty) {
      // ignore: avoid_print
      print('[live] 服务端小说库为空，跳过小说阅读器链路');
      return;
    }

    final bookId = novels.items.first.id;
    final detail = await live.content.detail(ContentKind.novel, bookId);
    expect(detail.item.title, isNotEmpty);
    expect(detail.chapters, isNotEmpty, reason: '小说详情应内联章节目录');

    final chapterId = detail.chapters.first.id;
    final chapter = await live.content.novelChapterContent(bookId, chapterId);
    expect(chapter.id, chapterId);
    expect(chapter.title, isNotEmpty);
    expect(chapter.bookId, anyOf(isNull, bookId));
    if (chapter.hasContent) {
      expect(chapter.text, isNotNull, reason: '有正文时纯文本不应为空');
      expect(chapter.text!.trim(), isNotEmpty);
    }
    // ignore: avoid_print
    print(
      '[live] 小说阅读器: book=${detail.item.title} chapters=${detail.chapters.length} '
      'chapter=${chapter.title} hasContent=${chapter.hasContent} '
      'words=${chapter.wordCount} prev=${chapter.prevId != null} next=${chapter.nextId != null}',
    );
  });

  test('真实后端：漫画详情 → 章节图片可读取且图片资源可访问（漫画阅读器链路）', () async {
    if (!backendReachable) {
      return;
    }

    final live = await _LiveContent.open(
      host: host,
      port: port,
      username: username,
      password: password,
    );
    addTearDown(live.close);

    final comics = await live.content.list(ContentKind.comic, pageSize: 5);
    expect(comics.items, isNotNull);
    if (comics.items.isEmpty) {
      // ignore: avoid_print
      print('[live] 服务端漫画库为空，跳过漫画阅读器链路');
      return;
    }

    final albumId = comics.items.first.id;
    final detail = await live.content.detail(ContentKind.comic, albumId);
    expect(detail.chapters, isNotEmpty, reason: '漫画详情应内联章节目录');

    final chapterId = detail.chapters.first.id;
    final pages = await live.content.comicChapterPages(albumId, chapterId);
    expect(pages.chapterId, chapterId);
    expect(pages.pages, isNotEmpty, reason: '章节应返回图片页');

    // 图片地址必须可访问（客户端阅读器直接交给图片组件加载）
    final image = pages.pages.first.imageUri;
    expect(image.hasScheme, isTrue, reason: '图片地址应为绝对地址');
    final fetched = await _fetchBytes(image);
    expect(fetched, isNotNull, reason: '章节图片应可下载: $image');
    expect(
      fetched!.mimeType,
      startsWith('image/'),
      reason: '图片资源应返回图片类型，实际为 ${fetched.mimeType}',
    );
    // ignore: avoid_print
    print(
      '[live] 漫画阅读器: album=${detail.item.title} chapters=${detail.chapters.length} '
      'chapter=${pages.title} pages=${pages.pageCount} '
      'image=${image.toString()} bytes=${fetched.length} type=${fetched.mimeType}',
    );
  });

  test('真实后端：影视 / 人物详情与封面资源地址', () async {
    if (!backendReachable) {
      return;
    }

    final live = await _LiveContent.open(
      host: host,
      port: port,
      username: username,
      password: password,
    );
    addTearDown(live.close);

    for (final kind in <ContentKind>[ContentKind.media, ContentKind.people]) {
      final list = await live.content.list(kind, pageSize: 5);
      if (list.items.isEmpty) {
        // ignore: avoid_print
        print('[live] ${kind.pathSegment} 列表为空，跳过详情校验');
        continue;
      }
      final detail = await live.content.detail(kind, list.items.first.id);
      expect(detail.item.title, isNotEmpty);
      final cover = detail.item.coverUri;
      if (cover != null) {
        expect(cover.hasScheme, isTrue, reason: '封面应为绝对地址');
        final fetched = await _fetchBytes(cover);
        if (fetched != null) {
          expect(
            fetched.mimeType,
            startsWith('image/'),
            reason: '封面资源应返回图片类型，实际为 ${fetched.mimeType}',
          );
        }
      }
      // ignore: avoid_print
      print(
        '[live] ${kind.pathSegment} 详情: title=${detail.item.title} '
        'attributes=${detail.attributes.length} gallery=${detail.gallery.length} '
        'related=${detail.related.length} cover=$cover',
      );
    }
  });
}

/// 真实后端联调上下文：登录后的会话 + 内容仓库。
final class _LiveContent {
  _LiveContent._(this.session, this.server, this.content);

  /// 网络会话（持有令牌）。
  final _LiveSession session;

  /// 服务端档案。
  final ServerProfile server;

  /// 内容仓库。
  final ContentRepositoryImpl content;

  /// 登录并构造内容仓库。
  static Future<_LiveContent> open({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    final session = _LiveSession();
    final auth = AuthRepositoryImpl(apiFactory: session.apiForProfile);
    final server = ServerProfile(
      id: 'live-backend',
      name: 'Live AMMDS',
      host: host,
      port: port,
      dialect: ServerDialect.clientV1.code,
    );
    final result = await auth.login(
      server: server,
      credentials: AuthCredentials(username: username, password: password),
    );
    session.accessToken = result.tokens.accessToken;
    return _LiveContent._(
      session,
      server,
      ContentRepositoryImpl(apiFactory: () => session.apiForProfile(server)),
    );
  }

  /// 释放网络资源。
  void close() => session.close();
}

/// 图片下载结果。
final class _FetchedBytes {
  const _FetchedBytes({required this.length, required this.mimeType});

  /// 字节数。
  final int length;

  /// MIME 类型。
  final String mimeType;
}

/// 下载一个图片地址，失败返回 null。
Future<_FetchedBytes?> _fetchBytes(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
    }
    if (response.statusCode != 200) {
      return null;
    }
    return _FetchedBytes(
      length: length,
      mimeType: response.headers.contentType?.mimeType ?? '',
    );
  } on Object {
    return null;
  } finally {
    client.close();
  }
}

/// 探测后端是否在线。
Future<bool> _isReachable(String host, int port) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final request = await client.getUrl(
      Uri.parse('http://$host:$port/api/oauth/secret'),
    );
    final response = await request.close();
    await response.drain<void>();
    client.close();
    return response.statusCode == 200;
  } on Object {
    return false;
  }
}

/// 真实联调用的最小网络装配：按方言创建 API 实现。
final class _LiveSession {
  /// 登录后写入的访问令牌，用于给后续请求注入 `Authorization`。
  String? accessToken;

  final List<NetworkClient> _clients = <NetworkClient>[];

  /// 按「服务端 + 方言」创建 API。
  ServerApi apiFor(ServerProfile server, ServerDialect dialect) {
    final network = DioNetworkClient(
      baseUrl: server.baseUri.toString(),
      // 应用内由鉴权拦截器自动注入令牌；联调装配需要手动模拟同样的行为。
      interceptors: <Interceptor>[
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final token = accessToken;
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            handler.next(options);
          },
        ),
      ],
    );
    _clients.add(network);
    return switch (dialect) {
      ServerDialect.clientV1 => ClientApi(network: network, server: server),
      ServerDialect.ammdsPublic => AmmdsPublicApi(
        network: network,
        server: server,
      ),
    };
  }

  /// 按档案中记录的方言创建 API。
  ServerApi apiForProfile(ServerProfile server) =>
      apiFor(server, ServerDialect.fromProfile(server));

  /// 释放网络资源。
  void close() {
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
  }
}
