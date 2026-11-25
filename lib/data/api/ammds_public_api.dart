import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/network_client.dart';
import '../../core/utils/password_digest.dart';
import '../../core/utils/rsa_crypto.dart';
import '../../domain/entities/content.dart';
import '../../domain/entities/reading.dart';
import '../../domain/entities/server.dart';
import '../dto/api_dto.dart';
import 'server_api.dart';

/// AMMDS 既有服务端公开接口实现。
///
/// 与 [ClientApiPaths] 约定的 `/api/client/v1/**` 不同，这里对接的是服务端
/// **当前已经存在**的对外接口：
///
/// | 用途 | 接口 |
/// | --- | --- |
/// | 登录公钥 | `GET  /api/oauth/secret` → `data.secret`（Base64 SubjectPublicKeyInfo） |
/// | 登录 | `POST /api/oauth/login`（密码为 `RSA(MD5^5(明文))`） |
/// | 登出 | `POST /api/oauth/logout` |
/// | 连通性 | `GET  /api/oauth/secret` |
/// | 用户信息 | `GET  /api/admin/user/info`（`Authorization: Bearer <jwt>`） |
/// | 影视 | `POST /api/pub/media/search`、`GET /api/pub/media/details/{id}` |
/// | 人物 | `POST /api/pub/actor/search`、`GET /api/pub/actor/details/{id}` |
/// | 小说 | `GET  /api/pub/novel/search`、`GET /api/pub/novel/details/{id}` |
/// | 漫画 | `GET  /api/pub/comic/search`、`GET /api/pub/comic/details/{id}` |
///
/// 鉴权失败时服务端返回 **HTTP 200 + 业务码 401**，因此这里把业务码 401/403
/// 归一化为 [AuthError]，与 HTTP 401 行为保持一致。
final class AmmdsPublicApi implements ServerApi {
  /// 创建实现。
  AmmdsPublicApi({required this.network, required this.server});

  /// 网络客户端。
  final NetworkClient network;

  @override
  final ServerProfile server;

  @override
  Uri get baseUri => server.baseUri;

  @override
  Future<ServerInfoDto> fetchServerInfo() async {
    // 既有服务端没有独立的服务端信息接口：
    // 名称 / 版本 / API 版本由发现协议提供，这里只做能力探测。
    await ping();
    return ServerInfoDto(
      serverId: server.id,
      name: server.name,
      serverVersion: server.serverVersion,
      apiVersion: server.apiVersion,
      https: server.isHttps,
      capabilities: const <String, bool>{
        'media': true,
        'people': true,
        'novel': true,
        'comic': true,
      },
    );
  }

  @override
  Future<void> ping() async {
    // /api/oauth/secret 属于免鉴权路径，且始终可用，适合作为连通性探测。
    await network.get<Object?>(
      '/api/oauth/secret',
      options: const NetworkOptions(requiresAuth: false),
      decode: (data) => data,
    );
  }

  @override
  Future<String?> fetchPublicKey() async {
    final key = await network.get<String?>(
      '/api/oauth/secret',
      options: const NetworkOptions(requiresAuth: false),
      decode: (data) {
        final map = JsonReader.object(data);
        if (map == null) {
          return null;
        }
        return JsonReader.string(
          map['secret'] ?? map['publicKey'] ?? map['public_key'],
        );
      },
    );
    return key;
  }

  @override
  Future<SplashConfigDto> fetchSplash() async {
    // 既有公开接口没有开屏配置，统一返回官方开屏由客户端本地渲染。
    return SplashConfigDto.official;
  }

  @override
  Future<LoginResponseDto> login({
    required String username,
    required String password,
  }) async {
    final encrypted = await _encryptLoginPassword(password);
    final token = await network.post<TokenDto>(
      '/api/oauth/login',
      body: <String, Object?>{
        'username': username,
        // 服务端未提供公钥时退回明文（兼容未启用加密的部署）
        'password': encrypted ?? password,
      },
      options: const NetworkOptions(requiresAuth: false),
      decode: TokenDto.fromJson,
    );
    // 既有服务端的登录响应只包含令牌，这里顺带拉取用户信息，
    // 使上层无需感知方言差异。
    UserDto? user;
    try {
      user = await fetchProfile(token.accessToken);
    } on Object catch (error) {
      AppLogger.debug(
        'AmmdsPublicApi',
        'profile fetch after login skipped: '
            '${AppLogger.sanitize('$error')}',
      );
    }
    return LoginResponseDto(token: token, user: user);
  }

  @override
  Future<TokenDto> refresh(String refreshToken) async {
    // 既有服务端未提供刷新令牌接口：令牌过期后必须重新登录。
    throw const AuthError('Server does not support token refresh');
  }

  @override
  Future<void> logout(String accessToken) => network.post<void>(
    '/api/oauth/logout',
    body: const <String, Object?>{},
    options: NetworkOptions(
      requiresAuth: true,
      headers: <String, String>{'Authorization': 'Bearer $accessToken'},
    ),
    decode: (_) {},
  );

  @override
  Future<void> validateSession(String accessToken) async {
    await fetchProfile(accessToken);
  }

  @override
  Future<UserDto> fetchProfile(String accessToken) => network.get<UserDto>(
    '/api/admin/user/info',
    options: NetworkOptions(
      requiresAuth: true,
      headers: <String, String>{'Authorization': 'Bearer $accessToken'},
    ),
    decode: UserDto.fromJson,
  );

  @override
  Future<PageDto<ContentItemDto>> listContent(
    ContentKind kind, {
    String? cursor,
    int pageSize = 20,
    String? keyword,
    String? category,
  }) {
    final page = int.tryParse(cursor ?? '1') ?? 1;
    final query = <String, Object?>{
      'current': page,
      'size': pageSize,
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      if (category != null && category.isNotEmpty) 'label': category,
    };
    final searching = keyword != null && keyword.isNotEmpty;
    final options = NetworkOptions(
      kind: searching ? RequestKind.search : RequestKind.normal,
      retry: true,
      requiresAuth: false,
    );
    PageDto<ContentItemDto> decode(Object? data) =>
        PageDto.fromJson<ContentItemDto>(data, ContentItemDto.fromJson);

    return switch (kind) {
      // 影视 / 人物搜索为 POST，请求体为筛选条件
      ContentKind.media => network.post<PageDto<ContentItemDto>>(
        '/api/pub/media/search',
        body: <String, Object?>{
          if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
          if (category != null && category.isNotEmpty) 'label': category,
        },
        query: query,
        options: options,
        decode: decode,
      ),
      ContentKind.people => network.post<PageDto<ContentItemDto>>(
        '/api/pub/actor/search',
        body: <String, Object?>{
          if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
          if (category != null && category.isNotEmpty) 'label': category,
        },
        query: query,
        options: options,
        decode: decode,
      ),
      // 小说 / 漫画列表为 GET
      ContentKind.novel => network.get<PageDto<ContentItemDto>>(
        '/api/pub/novel/search',
        query: query,
        options: options,
        decode: decode,
      ),
      ContentKind.comic => network.get<PageDto<ContentItemDto>>(
        '/api/pub/comic/search',
        query: query,
        options: options,
        decode: decode,
      ),
    };
  }

  @override
  Future<ContentDetailDto> detail(ContentKind kind, String id) =>
      network.get<ContentDetailDto>(
        '${_publicSegment(kind)}/details/$id',
        options: _publicOptions,
        decode: ContentDetailDto.fromJson,
      );

  @override
  Future<List<ChapterDto>> chapters(ContentKind kind, String id) async {
    // 既有服务端的详情响应已内联章节列表；
    // 单独请求章节时回退为读取详情并取其中的 chapters 字段。
    final detail = await this.detail(kind, id);
    return detail.chapters;
  }

  String _publicSegment(ContentKind kind) => switch (kind) {
    ContentKind.media => '/api/pub/media',
    ContentKind.people => '/api/pub/actor',
    ContentKind.novel => '/api/pub/novel',
    ContentKind.comic => '/api/pub/comic',
  };

  /// 小说章节正文（既有公开接口 `/api/pub/novel/chapter/{chapterId}`）。
  ///
  /// 该接口不接受书籍 ID，正文为 HTML；DTO 会兼容解析并在必要时由客户端转换为纯文本。
  @override
  Future<ChapterContentDto> novelChapterContent(
    String bookId,
    String chapterId,
  ) => network.get<ChapterContentDto>(
    '/api/pub/novel/chapter/$chapterId',
    options: _publicOptions,
    decode: ChapterContentDto.fromJson,
  );

  /// 漫画章节图片（既有公开接口 `/api/pub/comic/chapter/pages`）。
  ///
  /// 返回体只有章节 ID / 标题与 `imagePath`，相册与相邻章节由上层结合章节列表补齐。
  @override
  Future<ComicChapterPagesDto> comicChapterPages(
    String albumId,
    String chapterId,
  ) => network.get<ComicChapterPagesDto>(
    '/api/pub/comic/chapter/pages',
    query: <String, Object?>{'chapterId': chapterId},
    options: _publicOptions,
    decode: ComicChapterPagesDto.fromJson,
  );

  /// 阅读进度：既有公开接口（`GET /api/pub/{novel|comic}/progress`）。
  ///
  /// 与书城侧共用同一份进度数据：请求参数为内容 ID 的驼峰字段名，
  /// 返回体就是进度实体本身（字段为驼峰），由 DTO 统一兼容解析。
  @override
  Future<ReadingProgressDto?> fetchReadingProgress(
    ContentKind kind,
    String id,
  ) async {
    final segment = _progressSegment(kind);
    if (segment == null) {
      return null;
    }
    final data = await network.get<Object?>(
      segment,
      query: <String, Object?>{
        kind == ContentKind.novel ? 'novelBookId' : 'comicAlbumId': id,
      },
      options: _publicOptions,
    );
    return ReadingProgressDto.fromJson(data);
  }

  /// 阅读进度同步：既有公开接口（`POST /api/pub/{novel|comic}/progress/save`）。
  @override
  Future<void> saveReadingProgress(ReadingProgress progress) async {
    final segment = _progressSegment(progress.kind);
    if (segment == null || progress.chapterId == null) {
      return;
    }
    final body = <String, Object?>{
      'chapterId': progress.chapterId,
      'chapterTitle': progress.chapterTitle,
      'chapterIndex': progress.chapterIndex,
    };
    if (progress.kind == ContentKind.novel) {
      body['novelBookId'] = progress.id;
      // 客户端用 0~100 百分数，服务端存 0~1 比例
      body['percent'] = progress.page.clamp(0, 100) / 100;
    } else {
      body['comicAlbumId'] = progress.id;
      body['pageNo'] = progress.page;
    }
    await network.post<void>(
      '$segment/progress/save',
      body: body,
      options: _publicOptions,
    );
  }

  /// 播放决策：既有公开方言没有播放接口，直接返回「不支持」并说明原因
  /// （不抛异常，让界面能展示明确提示而不是错误页）。
  @override
  Future<PlaybackDecisionDto> decidePlayback({
    required String fileId,
    required Map<String, Object?> capability,
  }) async => PlaybackDecisionDto.unsupported('当前服务端为公开接口方言，不支持播放能力协商');

  /// 公开方言（`/api/pub/**`）的请求选项。
  ///
  /// 这些接口在服务端属于免鉴权前缀，**不能标记为需要鉴权**：否则
  /// `AuthInterceptor` 会注入令牌，并在令牌临近过期时调用 [refresh]，
  /// 而公开方言没有刷新接口（[refresh] 直接抛错），会把会话判为失效并清空
  /// 登录状态。因此这里显式声明不需要鉴权。
  static const NetworkOptions _publicOptions = NetworkOptions(
    requiresAuth: false,
  );

  /// 阅读进度接口前缀；不支持进度的内容类型返回 null。
  static String? _progressSegment(ContentKind kind) => switch (kind) {
    ContentKind.novel => '/api/pub/novel',
    ContentKind.comic => '/api/pub/comic',
    _ => null,
  };

  /// 依据服务端约定生成登录密码密文：`RSA(MD5^5(明文))`。
  Future<String?> _encryptLoginPassword(String password) async {
    try {
      final publicKey = await fetchPublicKey();
      if (publicKey == null || publicKey.isEmpty) {
        return null;
      }
      final digest = PasswordDigest.loginDigest(password);
      return RsaPublicKey.parse(publicKey).encryptUtf8ToBase64(digest);
    } on Object catch (error) {
      AppLogger.warning(
        'AmmdsPublicApi',
        'password encryption unavailable, falling back to plain field',
        error,
      );
      return null;
    }
  }
}
