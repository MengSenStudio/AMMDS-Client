import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/playback_capability.dart';
import '../../domain/entities/auth.dart';
import '../../domain/entities/content.dart';
import '../../domain/entities/server.dart';
import '../../domain/entities/splash.dart';
import '../../domain/repositories/repositories.dart';
import '../api/server_api.dart';
import '../api/server_dialect.dart';
/// 认证仓库实现（文档 #19 / #26 / #29 / #89）。
///
/// 与具体接口方言无关：密码加密、登录路径、用户信息字段差异
/// 全部由 [ServerApi] 的实现承担。
final class AuthRepositoryImpl implements AuthRepository {
  /// 创建实现。
  AuthRepositoryImpl({required this.apiFactory});

  /// 按服务端档案创建 API 客户端（依据档案中记录的方言选择实现）。
  final ServerApi Function(ServerProfile server) apiFactory;

  @override
  Future<AuthResult> login({
    required ServerProfile server,
    required AuthCredentials credentials,
  }) async {
    final api = apiFactory(server);
    final response = await api.login(
      username: credentials.username,
      password: credentials.password,
    );
    final result = _map(() => response.toEntity(base: api.baseUri));
    final user = result.user;
    if (user.id.isNotEmpty || user.username.isNotEmpty) {
      return result;
    }
    // 服务端未在登录响应中返回用户信息时，主动拉取一次。
    final profile = await api.fetchProfile(result.tokens.accessToken);
    return AuthResult(
      tokens: result.tokens,
      user: _map(() => profile.toEntity(base: api.baseUri)),
    );
  }

  @override
  Future<AuthTokens> refresh({
    required ServerProfile server,
    required String refreshToken,
  }) async {
    final api = apiFactory(server);
    return (await api.refresh(refreshToken)).toEntity();
  }

  @override
  Future<void> logout({
    required ServerProfile server,
    required String accessToken,
  }) async {
    await apiFactory(server).logout(accessToken);
  }

  @override
  Future<UserProfile> fetchProfile({
    required ServerProfile server,
    required String accessToken,
  }) async {
    final api = apiFactory(server);
    final dto = await api.fetchProfile(accessToken);
    return _map(() => dto.toEntity(base: api.baseUri));
  }

  @override
  Future<bool> validateSession({
    required ServerProfile server,
    required String accessToken,
  }) async {
    final api = apiFactory(server);
    try {
      await api.validateSession(accessToken);
      return true;
    } on AuthError {
      return false;
    } on ServerError catch (error) {
      if (error.statusCode == 401 ||
          error.statusCode == 403 ||
          error.code == '401' ||
          error.code == '403') {
        return false;
      }
      rethrow;
    }
  }

  /// 把 DTO → Domain 的转换错误统一归一化为 [ParseError]（文档 #32）。
  ///
  /// 避免解析异常（如字段缺失）以原始异常形式泄漏到 UI 层，
  /// 导致无法按统一错误模型展示。
  static T _map<T>(T Function() convert) {
    try {
      return convert();
    } on AppException {
      rethrow;
    } on Object catch (error) {
      throw ParseError('Failed to parse server response', cause: error);
    }
  }
}

/// 服务端仓库实现（文档 #90）。
final class ServerRepositoryImpl implements ServerRepository {
  /// 创建实现。
  ServerRepositoryImpl({required this.apiFactory, required this.discoverer});

  /// 按候选档案与方言创建 API 客户端。
  final ServerApi Function(ServerProfile server, ServerDialect dialect)
  apiFactory;

  /// 发现回调：由装配层注入 [DiscoveryService.discover]。
  final Future<List<ServerProfile>> Function({
    void Function(ServerProfile server)? onServerFound,
  })
  discoverer;

  @override
  Future<List<ServerProfile>> discover({
    void Function(ServerProfile server)? onServerFound,
  }) => discoverer(onServerFound: onServerFound);

  @override
  Future<ServerProfile> probe(ServerProfile candidate) async {
    // 先用档案中记录的方言（或默认 Client API）探测；
    // 失败时再尝试另一种方言，并把结果写回档案。
    final preferred = ServerDialect.fromProfile(candidate);
    final order = <ServerDialect>[
      preferred,
      ...ServerDialect.values.where((dialect) => dialect != preferred),
    ];
    Object? lastError;
    for (final dialect in order) {
      try {
        final api = apiFactory(candidate, dialect);
        await api.ping();
        return _stamp(candidate, dialect);
      } on Object catch (error) {
        lastError = error;
        AppLogger.debug(
          'ServerRepositoryImpl',
          'dialect ${dialect.code} probe failed: '
              '${AppLogger.sanitize('$error')}',
        );
      }
    }
    throw lastError is AppException
        ? lastError
        : NetworkError('Server is not reachable', cause: lastError);
  }

  @override
  Future<ServerProfile> fetchServerInfo(ServerProfile server) async {
    final dialect = ServerDialect.fromProfile(server);
    final api = apiFactory(server, dialect);
    final info = await api.fetchServerInfo();
    final apiVersion = info.apiVersion ?? server.apiVersion;
    if (!_isApiVersionSupported(apiVersion)) {
      throw const ServerError(
        'Server API version is not compatible with this client',
        code: 'incompatible_version',
      );
    }
    return _stamp(
      server.copyWith(
        name: info.name ?? server.name,
        serverVersion: info.serverVersion ?? server.serverVersion,
        apiVersion: apiVersion,
        capabilities: info.capabilities.isEmpty
            ? server.capabilities
            : info.capabilities,
        lastConnectedAt: DateTime.now(),
      ),
      dialect,
    );
  }

  static ServerProfile _stamp(ServerProfile profile, ServerDialect dialect) =>
      profile.copyWith(dialect: dialect.code);

  /// 开屏配置的等待上限。
  ///
  /// 开屏处于启动关键路径：服务端不可达时必须尽快回落到本地官方开屏，
  /// 不能让用户盯着空白等待完整的连接超时。
  static const Duration _splashTimeout = Duration(milliseconds: 1500);

  @override
  Future<SplashConfig> fetchSplashConfig(
    ServerProfile server, {
    required String fallbackProductName,
    required String fallbackCopyright,
  }) async {
    final local = SplashConfig.local(
      productName: fallbackProductName,
      copyright: fallbackCopyright,
    );
    try {
      final api = apiFactory(server, ServerDialect.fromProfile(server));
      final dto = await api.fetchSplash().timeout(_splashTimeout);
      return dto.toEntity(
        fallbackProductName: fallbackProductName,
        fallbackCopyright: fallbackCopyright,
        base: api.baseUri,
      );
    } on Object catch (error) {
      AppLogger.debug(
        'ServerRepositoryImpl',
        'splash config unavailable, using local splash: '
            '${AppLogger.sanitize('$error')}',
      );
      return local;
    }
  }

  static bool _isApiVersionSupported(String apiVersion) {
    final normalized = apiVersion.trim().toLowerCase();
    // v1 / 1 / 1.0 / 1.0.0 均视为兼容。
    return normalized == 'v1' ||
        normalized == '1' ||
        normalized == '1.0' ||
        normalized == '1.0.0';
  }
}

/// 内容仓库实现（文档 #37 ~ #40 / #69 / #70）。
final class ContentRepositoryImpl implements ContentRepository {
  /// 创建实现。
  ContentRepositoryImpl({required this.apiFactory});

  /// 按当前服务端创建 API 客户端。
  final ServerApi Function() apiFactory;

  @override
  Future<PageResult<ContentItem>> list(
    ContentKind kind, {
    String? cursor,
    int pageSize = 20,
    String? keyword,
    String? category,
  }) async {
    final api = apiFactory();
    final dto = await api.listContent(
      kind,
      cursor: cursor,
      pageSize: pageSize,
      keyword: keyword,
      category: category,
    );
    final base = api.baseUri;
    return dto.toEntity((item) => item.toEntity(base: base));
  }

  @override
  Future<ContentDetail> detail(ContentKind kind, String id) async {
    final api = apiFactory();
    final dto = await api.detail(kind, id);
    var detail = dto.toEntity(base: api.baseUri);
    if (detail.chapters.isEmpty &&
        (kind == ContentKind.novel || kind == ContentKind.comic)) {
      final chapters = await this.chapters(kind, id);
      detail = ContentDetail(
        item: detail.item,
        overview: detail.overview,
        episodeCount: detail.episodeCount,
        status: detail.status,
        author: detail.author,
        chapters: chapters,
        related: detail.related,
      );
    }
    return detail;
  }

  @override
  Future<List<ContentChapter>> chapters(ContentKind kind, String id) async {
    final api = apiFactory();
    final dtos = await api.chapters(kind, id);
    return dtos.map((dto) => dto.toEntity()).toList(growable: false);
  }

  @override
  Future<ChapterContent> novelChapterContent(
    String bookId,
    String chapterId,
  ) async {
    final api = apiFactory();
    final dto = await api.novelChapterContent(bookId, chapterId);
    return dto.toEntity();
  }

  @override
  Future<ComicChapterPages> comicChapterPages(
    String albumId,
    String chapterId,
  ) async {
    final api = apiFactory();
    final dto = await api.comicChapterPages(albumId, chapterId);
    return dto.toEntity(base: api.baseUri);
  }

  @override
  Future<PlaybackDecision> playbackDecision(String fileId) async {
    final api = apiFactory();
    final dto = await api.decidePlayback(
      fileId: fileId,
      capability: PlaybackCapability.detect(),
    );
    final decision = dto.toEntity();
    final url = decision.url;
    if (url == null || url.isEmpty) {
      return decision;
    }
    // 服务端返回相对地址，这里统一补成绝对地址；令牌由播放页追加，
    // 因为 <video> 无法自定义请求头（服务端支持 ?token= 一次性校验）。
    return PlaybackDecision(
      mode: decision.mode,
      url: api.baseUri.resolve(url).toString(),
      mimeType: decision.mimeType,
      reason: decision.reason,
      targetBitrate: decision.targetBitrate,
    );
  }
}
