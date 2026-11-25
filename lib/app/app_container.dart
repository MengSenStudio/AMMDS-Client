import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/discovery/discovery_service.dart';
import '../core/discovery/discovery_transport.dart';
import '../core/logging/app_logger.dart';
import '../core/network/interceptors/auth_interceptor.dart';
import '../core/network/interceptors/network_logging_interceptor.dart';
import '../core/network/network_client.dart';
import '../core/platform/desktop_shell.dart';
import '../core/storage/credential_store.dart';
import '../core/storage/storage.dart';
import '../core/utils/resource_uri.dart';
import '../data/api/ammds_public_api.dart';
import '../data/api/client_api.dart';
import '../data/api/server_api.dart';
import '../data/api/server_dialect.dart';
import '../data/repositories/promote_repository_impl.dart';
import '../data/repositories/reading_repository_impl.dart';
import '../data/repositories/repositories.dart';
import '../data/repositories/settings_repository_impl.dart';
import '../domain/entities/auth.dart';
import '../domain/entities/content.dart';
import '../domain/entities/reading.dart';
import '../domain/entities/server.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/bootstrap_manager.dart';
import '../domain/services/server_manager.dart';
import '../domain/services/session_manager.dart';

/// 全局依赖容器（文档 #92：统一依赖入口，业务代码不自行创建单例）。
///
/// 关键点：网络层按「当前服务端」动态构建，令牌注入与刷新由
/// [SessionManager] 统一完成，业务代码只依赖 Repository 接口。
final preferencesStorageProvider = Provider<PreferencesStorage>(
  (ref) =>
      throw UnimplementedError('preferencesStorageProvider must be overridden'),
);

/// 安全存储。
final secureStorageProvider = Provider<SecureStorage>(
  (ref) => throw UnimplementedError('secureStorageProvider must be overridden'),
);

/// 运行环境。
final environmentProvider = Provider<AppEnvironment>(
  (ref) => AppConstants.environment,
);

/// 桌面外壳（托盘图标 / 关闭即最小化 / 开机自启）。
///
/// 实例是进程级单例，并在 `main()` 中完成初始化（见 `desktop_shell.dart`），
/// 因此这里只把同一实例交给界面：设置页据此判断是否展示「开机自启」。
final desktopShellProvider = Provider<DesktopShell>((ref) => desktopShell);

/// 设置仓库。
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) =>
      SettingsRepositoryImpl(storage: ref.watch(preferencesStorageProvider)),
);

/// 会话持久化。
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(secureStorage: ref.watch(secureStorageProvider)),
);

/// 「记住密码」凭据存取（用户名与密码只进安全存储）。
final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => CredentialStore(
    secureStorage: ref.watch(secureStorageProvider),
    preferencesStorage: ref.watch(preferencesStorageProvider),
  ),
);

/// 网络适配器覆盖点（测试注入 MockAdapter）。
final httpAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

/// 每个服务端一个「API 会话」。
///
/// 两套接口方言共享同一个 [NetworkClient]（同地址、同拦截器），
/// 因此切换方言不会产生额外的连接与鉴权开销。
final class ServerApiSession {
  /// 创建会话。
  ServerApiSession({
    required this.server,
    required this.network,
    required this.interceptor,
  }) : clientV1 = ClientApi(network: network, server: server),
       ammdsPublic = AmmdsPublicApi(network: network, server: server);

  /// 服务端。
  final ServerProfile server;

  /// 网络客户端。
  final NetworkClient network;

  /// 鉴权拦截器（便于测试断言）。
  final AuthInterceptor interceptor;

  /// Client API 方言实现。
  final ClientApi clientV1;

  /// 既有公开接口方言实现。
  final AmmdsPublicApi ammdsPublic;

  /// 依据方言选择实现。
  ServerApi select(ServerDialect dialect) => switch (dialect) {
    ServerDialect.clientV1 => clientV1,
    ServerDialect.ammdsPublic => ammdsPublic,
  };

  /// 关闭网络资源。
  void close() => network.close();
}

/// 构建某个服务端的 API 会话。
///
/// 说明：鉴权拦截器需要的回调**延迟解析** [sessionManagerProvider]。
/// 若在此处直接 `ref.read`，会形成
/// `SessionManager → AuthRepository → DioNetworkClient → SessionManager`
/// 的环形依赖；延迟到实际发起请求时再解析即可打破该环。
ServerApiSession buildServerApiSession(Ref ref, ServerProfile server) {
  final logging = NetworkLoggingInterceptor(
    enabled: !AppConstants.isProduction,
  );
  final auth = AuthInterceptor(
    readAccessToken: () =>
        ref.read(sessionManagerProvider).currentAccessToken(),
    refreshToken: () => ref.read(sessionManagerProvider).refresh(),
    onAuthenticationLost: (error) {
      AppLogger.warning(
        'AppContainer',
        'authentication lost, session cleared',
        error,
      );
    },
  );
  final network = DioNetworkClient(
    baseUrl: server.baseUri.toString(),
    interceptors: <Interceptor>[logging, auth],
    adapter: ref.read(httpAdapterProvider),
  );
  auth.attach(network.raw);
  return ServerApiSession(server: server, network: network, interceptor: auth);
}

/// 创建「按服务端 + 方言」解析 API 的工厂，并缓存每个服务端的会话。
ServerApi Function(ServerProfile server, ServerDialect dialect)
serverApiFactory(Ref ref) {
  final cache = <String, ServerApiSession>{};
  ServerApiSession sessionFor(ServerProfile server) {
    final key = '${server.protocol}://${server.host}:${server.port}';
    final cached = cache[key];
    if (cached != null) {
      return cached;
    }
    final session = buildServerApiSession(ref, server);
    cache[key] = session;
    ref.onDispose(session.close);
    return session;
  }

  return (server, dialect) => sessionFor(server).select(dialect);
}

/// 按服务端档案中记录的方言解析 API 的便捷工厂。
ServerApi Function(ServerProfile server) serverApiFor(Ref ref) {
  final factory = serverApiFactory(ref);
  return (server) => factory(server, ServerDialect.fromProfile(server));
}

/// 认证仓库。
///
/// 客户端内部的鉴权拦截器在**运行期**才解析 [sessionManagerProvider]，
/// 因此这里不会与 [sessionManagerProvider] 形成构造期环。
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(apiFactory: serverApiFor(ref)),
);

/// 会话管理器。
final sessionManagerProvider = Provider<SessionManager>((ref) {
  final manager = SessionManager(
    resolveAuthRepository: () => ref.read(authRepositoryProvider),
    sessionStore: ref.watch(sessionStoreProvider),
  );
  // 把令牌的唯一事实来源接给资源地址解析器：远端图片走已登录的服务端代理
  // （/api/client/v1/resource/proxyImage），而图片由 Image.network 加载、
  // 无法自定义请求头，只能把令牌放进 URL。会话管理器是唯一知道当前令牌的地方，
  // 在这里注入可以避免资源工具反向依赖会话层，也避免把令牌一路穿过 DTO 映射。
  ResourceUri.accessTokenReader = () => manager.session?.tokens.accessToken;
  return manager;
});

/// 发现传输（可在测试中覆盖为内存实现）。
final discoveryTransportProvider = Provider<DiscoveryTransport>(
  (ref) => UdpDiscoveryTransport(),
);

/// 发现节奏调优（测试可覆盖为极短间隔，避免等待真实探测窗口）。
final discoveryTuningProvider = Provider<DiscoveryTuning>(
  (ref) => const DiscoveryTuning(),
);

/// 发现服务。
final discoveryServiceProvider = Provider<DiscoveryService>(
  (ref) => DiscoveryService(
    transport: ref.watch(discoveryTransportProvider),
    tuning: ref.watch(discoveryTuningProvider),
  ),
);

/// 服务端仓库。
final serverRepositoryProvider = Provider<ServerRepository>(
  (ref) => ServerRepositoryImpl(
    apiFactory: serverApiFactory(ref),
    discoverer: ({void Function(ServerProfile server)? onServerFound}) async {
      final outcome = await ref
          .read(discoveryServiceProvider)
          .discover(
            onServerFound: (response) => onServerFound?.call(
              ServerManager.profileFromDiscovery(response),
            ),
          );
      return outcome.servers
          .map(ServerManager.profileFromDiscovery)
          .toList(growable: false);
    },
  ),
);

/// 服务端管理器。
final serverManagerProvider = Provider<ServerManager>(
  (ref) => ServerManager(
    serverRepository: ref.watch(serverRepositoryProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    discoveryService: ref.watch(discoveryServiceProvider),
  ),
);

/// 内容仓库：按当前服务端动态解析。
///
/// 内容请求使用请求时的「当前服务端」，服务端切换后无需重建 Provider。
final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) => ContentRepositoryImpl(
    apiFactory: () {
      final server = ref.read(serverManagerProvider).activeServer;
      if (server == null) {
        throw StateError('No active server configured');
      }
      return serverApiFor(ref)(server);
    },
  ),
);

/// 阅读仓库：阅读设置与阅读进度（本地优先 + 服务端跨设备同步，文档 #39 / #40）。
final readingRepositoryProvider = Provider<ReadingRepository>(
  (ref) => ReadingRepositoryImpl(
    storage: ref.watch(preferencesStorageProvider),
    remote: _ServerReadingProgressRemote(ref),
  ),
);

/// 官方推送通告仓库。
///
/// 数据来自官方远端 JSON（与网页端同一地址），**不依赖当前服务端**，
/// 因此这里不需要按方言解析；「已读」按当日记录在本地。
final promoteRepositoryProvider = Provider<PromoteRepository>(
  (ref) => PromoteRepositoryImpl(storage: ref.watch(preferencesStorageProvider)),
);

/// 基于「当前服务端 + 方言」的阅读进度通道。
///
/// 未登录或未配置服务端时返回 null，使阅读进度退化为纯本地；
/// 请求失败由仓库侧兜底（读取回退本地、写入静默忽略），
/// 因此阅读体验不依赖服务端可用性。
final class _ServerReadingProgressRemote implements ReadingProgressRemote {
  /// 创建通道。
  _ServerReadingProgressRemote(this._ref);

  final Ref _ref;

  /// 解析当前可用的 API；不可用时返回 null。
  ServerApi? _api() {
    final server = _ref.read(serverManagerProvider).activeServer;
    if (server == null) {
      return null;
    }
    if (!_ref.read(sessionManagerProvider).isAuthenticated()) {
      return null;
    }
    return serverApiFor(_ref)(server);
  }

  @override
  Future<ReadingProgress?> fetch(ContentKind kind, String id) async {
    final api = _api();
    if (api == null) {
      return null;
    }
    final dto = await api.fetchReadingProgress(kind, id);
    return dto?.toEntity(kind, id);
  }

  @override
  Future<void> save(ReadingProgress progress) async {
    final api = _api();
    if (api == null) {
      return;
    }
    await api.saveReadingProgress(progress);
  }
}

/// 启动管理器。
final bootstrapManagerProvider = Provider<BootstrapManager>(
  (ref) => BootstrapManager(
    serverManager: ref.watch(serverManagerProvider),
    sessionManager: ref.watch(sessionManagerProvider),
  ),
);

/// 启动状态流。
final bootstrapStateProvider = StreamProvider<BootstrapState>(
  (ref) => ref.watch(bootstrapManagerProvider).stateStream,
);

/// 认证状态流。
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(sessionManagerProvider).stateStream,
);

/// 主题模式状态。
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// 主题模式控制器（文档 #5.1：默认 System）。
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  /// 从本地配置载入。
  Future<void> load() async {
    final raw = await ref.read(settingsRepositoryProvider).readThemeMode();
    state = _parse(raw);
  }

  /// 更新并持久化。
  Future<void> update(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsRepositoryProvider).writeThemeMode(_serialize(mode));
  }

  static ThemeMode _parse(String? raw) => switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static String _serialize(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}

/// 语言状态。
final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);

/// 语言控制器（文档 #7）。
class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  /// 从本地配置载入。
  Future<void> load() async {
    final raw = await ref.read(settingsRepositoryProvider).readLocale();
    state = parse(raw);
  }

  /// 更新并持久化。
  Future<void> update(Locale? locale) async {
    state = locale;
    final repository = ref.read(settingsRepositoryProvider);
    if (locale == null) {
      await repository.writeLocale('');
      return;
    }
    await repository.writeLocale(locale.languageCode);
  }

  /// 解析语言代码。
  static Locale? parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return switch (raw.toLowerCase()) {
      'zh' || 'zh-cn' => const Locale('zh'),
      'en' || 'en-us' => const Locale('en'),
      _ => null,
    };
  }
}

/// 启动环境提供的平台亮度。
final platformBrightnessProvider = Provider<Brightness>(
  (ref) => Brightness.light,
);

/// 当前服务端。
///
/// 用 `StreamProvider` 而不是普通 `Provider`：`ServerManager` 的内部状态
/// （档案列表、当前服务端）是可变对象，普通 `Provider` 只在首次读取时求值且
/// 不会随内部变更刷新，会导致界面长期停留在旧值。
final activeServerProvider = StreamProvider<ServerProfile?>(
  (ref) => ref.watch(serverManagerProvider).activeServerStream,
);

/// 服务器列表。
final serverProfilesProvider = Provider<List<ServerProfile>>(
  (ref) => ref.watch(serverManagerProvider).profiles,
);

/// 内容分页 Provider 的键。
final class ContentQuery {
  /// 创建查询键。
  const ContentQuery({required this.kind, this.keyword, this.category});

  /// 内容类型。
  final ContentKind kind;

  /// 关键词。
  final String? keyword;

  /// 分类。
  final String? category;

  @override
  bool operator ==(Object other) =>
      other is ContentQuery &&
      other.kind == kind &&
      other.keyword == keyword &&
      other.category == category;

  @override
  int get hashCode => Object.hash(kind, keyword, category);
}

/// 内容分页拉取器。
final class ContentPager {
  /// 创建分页器。
  ContentPager({required this.repository, required this.query});

  /// 仓库。
  final ContentRepository repository;

  /// 查询。
  final ContentQuery query;

  static const int pageSize = 20;

  /// 已加载数据。
  final List<ContentItem> items = <ContentItem>[];

  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;

  /// 是否还有更多。
  bool get hasMore => _hasMore;

  /// 当前页数据（只读）。
  List<ContentItem> get currentItems => List.unmodifiable(items);

  /// 拉取下一页。
  Future<List<ContentItem>> loadMore() async {
    if (_loading || !_hasMore) {
      return const <ContentItem>[];
    }
    _loading = true;
    try {
      final page = await repository.list(
        query.kind,
        cursor: _cursor,
        pageSize: pageSize,
        keyword: query.keyword,
        category: query.category,
      );
      items.addAll(page.items);
      _cursor = page.nextCursor ?? (page.hasMore ? '${items.length}' : null);
      _hasMore = page.hasMore;
      return page.items;
    } finally {
      _loading = false;
    }
  }

  /// 重新加载第一页。
  Future<List<ContentItem>> refresh() async {
    items.clear();
    _cursor = null;
    _hasMore = true;
    return loadMore();
  }
}

/// 当前内容仓库（依赖当前服务端）。
final contentPagerFactoryProvider =
    Provider<ContentPager Function(ContentQuery)>(
      (ref) =>
          (query) => ContentPager(
            repository: ref.watch(contentRepositoryProvider),
            query: query,
          ),
    );
