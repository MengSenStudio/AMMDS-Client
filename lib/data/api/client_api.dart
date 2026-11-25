import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/network_client.dart';
import '../../core/utils/rsa_crypto.dart';
import '../../domain/entities/content.dart';
import '../../domain/entities/reading.dart';
import '../../domain/entities/server.dart';
import '../dto/api_dto.dart';
import 'server_api.dart';

/// Client API 访问层（文档 #20 / #31 / #71）。
///
/// 对接文档约定的 `/api/client/v1/**` 接口：只负责「拼装请求 + 解析 DTO」，
/// 不做业务判断；上层 Repository 负责把 DTO 转成 Domain Entity 并归一化错误。
class ClientApi implements ServerApi {
  /// 创建 API 客户端。
  ClientApi({required this.network, required this.server});

  final NetworkClient network;

  /// 当前服务端档案。
  @override
  final ServerProfile server;

  /// 服务端根地址。
  @override
  Uri get baseUri => server.baseUri;

  /// 服务端信息与能力（文档 #81 / #82）。
  @override
  Future<ServerInfoDto> fetchServerInfo() async {
    try {
      return await network.get<ServerInfoDto>(
        ClientApiPaths.serverInfo,
        options: const NetworkOptions(requiresAuth: false),
        decode: ServerInfoDto.fromJson,
      );
    } on ServerError catch (error) {
      // 兼容：部分服务端只在根路径暴露版本信息。
      if (error.statusCode == 404) {
        return ServerInfoDto.fromJson(null);
      }
      rethrow;
    }
  }

  /// 连通性探测。
  @override
  Future<void> ping() => network.get<void>(
    ClientApiPaths.health,
    options: const NetworkOptions(requiresAuth: false),
    decode: (_) {},
  );

  /// 开屏配置（无需鉴权，文档 #14）。
  ///
  /// 服务端未提供该接口（404）时返回官方开屏，由客户端使用本地品牌资源兜底。
  /// 接收超时单独收紧：开屏是启动路径，不能让用户等待普通请求的超时时间。
  @override
  Future<SplashConfigDto> fetchSplash() async {
    try {
      return await network.get<SplashConfigDto>(
        ClientApiPaths.splash,
        options: const NetworkOptions(
          requiresAuth: false,
          receiveTimeout: Duration(seconds: 3),
        ),
        decode: SplashConfigDto.fromJson,
      );
    } on ServerError catch (error) {
      if (error.statusCode == 404) {
        return SplashConfigDto.official;
      }
      rethrow;
    }
  }

  /// 播放能力探测与决策（影视）。
  @override
  Future<PlaybackDecisionDto> decidePlayback({
    required String fileId,
    required Map<String, Object?> capability,
  }) => network.post<PlaybackDecisionDto>(
    '${ClientApiPaths.mediaFiles}/$fileId/playback',
    body: capability,
    decode: PlaybackDecisionDto.fromJson,
  );

  /// 服务端 RSA 公钥（与服务端既有登录约定保持一致）。
  ///
  /// 返回 `null` 表示服务端未启用公钥加密，此时退回明文密码字段。
  @override
  Future<String?> fetchPublicKey() async {
    try {
      final key = await network.get<String?>(
        '/api/oauth/secret',
        options: const NetworkOptions(requiresAuth: false),
        decode: (data) {
          final map = JsonReader.object(data);
          return map == null
              ? null
              : JsonReader.string(
                  map['secret'] ?? map['publicKey'] ?? map['public_key'],
                );
        },
      );
      return key;
    } on ServerError {
      return null;
    } on NetworkError {
      rethrow;
    } on ParseError {
      return null;
    }
  }

  /// 登录。
  ///
  /// Client API 约定密码为 `RSA(明文)`；服务端未提供公钥时退回明文。
  @override
  Future<LoginResponseDto> login({
    required String username,
    required String password,
  }) async {
    final encrypted = await _encryptPassword(password);
    final body = <String, Object?>{
      'username': username,
      'password': encrypted ?? password,
      'client': AppConstants.appId,
      'client_version': AppConstants.appVersion,
    };
    return network.post<LoginResponseDto>(
      ClientApiPaths.login,
      body: body,
      options: const NetworkOptions(requiresAuth: false),
      decode: LoginResponseDto.fromJson,
    );
  }

  Future<String?> _encryptPassword(String password) async {
    try {
      final publicKey = await fetchPublicKey();
      if (publicKey == null || publicKey.isEmpty) {
        return null;
      }
      return RsaPublicKey.parse(publicKey).encryptUtf8ToBase64(password);
    } on Object catch (error) {
      AppLogger.warning(
        'ClientApi',
        'RSA password encryption unavailable, falling back to plain field',
        error,
      );
      return null;
    }
  }

  /// 刷新令牌。
  @override
  Future<TokenDto> refresh(String refreshToken) => network.post<TokenDto>(
    ClientApiPaths.refresh,
    body: <String, Object?>{'refresh_token': refreshToken},
    options: const NetworkOptions(requiresAuth: false),
    decode: TokenDto.fromJson,
  );

  /// 登出。
  @override
  Future<void> logout(String accessToken) => network.post<void>(
    ClientApiPaths.logout,
    body: const <String, Object?>{},
    options: NetworkOptions(
      requiresAuth: true,
      headers: <String, String>{'Authorization': 'Bearer $accessToken'},
    ),
    decode: (_) {},
  );

  /// 校验会话。
  @override
  Future<void> validateSession(String accessToken) => network.get<void>(
    ClientApiPaths.session,
    options: NetworkOptions(
      requiresAuth: true,
      headers: <String, String>{'Authorization': 'Bearer $accessToken'},
    ),
    decode: (_) {},
  );

  /// 当前用户信息。
  @override
  Future<UserDto> fetchProfile(String accessToken) => network.get<UserDto>(
    ClientApiPaths.profile,
    options: NetworkOptions(
      requiresAuth: true,
      headers: <String, String>{'Authorization': 'Bearer $accessToken'},
    ),
    decode: UserDto.fromJson,
  );

  /// 内容列表 / 搜索。
  @override
  Future<PageDto<ContentItemDto>> listContent(
    ContentKind kind, {
    String? cursor,
    int pageSize = 20,
    String? keyword,
    String? category,
  }) {
    final searching = keyword != null && keyword.isNotEmpty;
    return network.get<PageDto<ContentItemDto>>(
      pathOf(kind),
      query: <String, Object?>{
        // ignore: use_null_aware_elements
        if (cursor != null) 'cursor': cursor,
        'page_size': pageSize,
        if (searching) 'keyword': keyword,
        if (category != null && category.isNotEmpty) 'category': category,
      },
      options: NetworkOptions(
        kind: searching ? RequestKind.search : RequestKind.normal,
        retry: true,
      ),
      decode: (data) =>
          PageDto.fromJson<ContentItemDto>(data, ContentItemDto.fromJson),
    );
  }

  /// 内容详情。
  @override
  Future<ContentDetailDto> detail(ContentKind kind, String id) =>
      network.get<ContentDetailDto>(
        '${pathOf(kind)}/$id',
        decode: ContentDetailDto.fromJson,
      );

  /// 章节列表。
  @override
  Future<List<ChapterDto>> chapters(ContentKind kind, String id) =>
      network.get<List<ChapterDto>>(
        '${pathOf(kind)}/$id/chapters',
        decode: (data) {
          final raw = data is List
              ? data
              : JsonReader.object(data)?['items'] ?? const <Object?>[];
          if (raw is! List) {
            return const <ChapterDto>[];
          }
          return raw.map(ChapterDto.fromJson).toList(growable: false);
        },
      );

  /// 内容接口路径（统一带 `/api/client/v1` 前缀，文档 #20 / #21）。
  String pathOf(ContentKind kind) => switch (kind) {
    ContentKind.media => ClientApiPaths.media,
    ContentKind.people => ClientApiPaths.people,
    ContentKind.novel => ClientApiPaths.novels,
    ContentKind.comic => ClientApiPaths.comics,
  };

  /// 小说章节正文（文档 #39）。
  @override
  Future<ChapterContentDto> novelChapterContent(
    String bookId,
    String chapterId,
  ) => network.get<ChapterContentDto>(
    ClientApiPaths.novelChapterContent(bookId, chapterId),
    decode: ChapterContentDto.fromJson,
  );

  /// 漫画章节图片（文档 #40）。
  @override
  Future<ComicChapterPagesDto> comicChapterPages(
    String albumId,
    String chapterId,
  ) => network.get<ComicChapterPagesDto>(
    ClientApiPaths.comicChapterPages(albumId, chapterId),
    decode: ComicChapterPagesDto.fromJson,
  );

  /// 阅读进度：仅小说 / 漫画有进度概念（文档 #39 / #40）。
  @override
  Future<ReadingProgressDto?> fetchReadingProgress(
    ContentKind kind,
    String id,
  ) async {
    final path = _progressPath(kind, id);
    if (path == null) {
      return null;
    }
    final data = await network.get<Object?>(path);
    return ReadingProgressDto.fromJson(data);
  }

  /// 阅读进度同步到服务端。
  @override
  Future<void> saveReadingProgress(ReadingProgress progress) async {
    final path = _progressPath(progress.kind, progress.id);
    if (path == null || progress.chapterId == null) {
      return;
    }
    await network.post<void>(
      path,
      body: ReadingProgressDto.clientRequestBody(progress),
    );
  }

  /// 阅读进度路径；不支持进度的内容类型返回 null。
  static String? _progressPath(ContentKind kind, String id) => switch (kind) {
    ContentKind.novel => ClientApiPaths.novelProgress(id),
    ContentKind.comic => ClientApiPaths.comicProgress(id),
    _ => null,
  };
}
