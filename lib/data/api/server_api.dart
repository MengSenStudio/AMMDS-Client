import '../../domain/entities/content.dart';
import '../../domain/entities/reading.dart';
import '../../domain/entities/server.dart';
import '../dto/api_dto.dart';

/// 服务端访问抽象。
///
/// AMMDS 生态中存在两套可用的服务端接口：
///
/// * **Client API**（`/api/client/v1/**`）：文档约定的客户端专用接口；
/// * **既有公开接口**（`/api/oauth/**`、`/api/pub/**`、`/api/admin/user/info`）：
///   当前服务端已经实现的对外接口。
///
/// 两者在路径、鉴权方式与密码约定上不同，但上层（Repository / Controller / UI）
/// 不应感知差异，因此统一抽象为 [ServerApi]，由装配层按服务端能力选择实现。
abstract interface class ServerApi {
  /// 当前服务端档案。
  ServerProfile get server;

  /// 服务端根地址，用于解析相对资源地址。
  Uri get baseUri;

  /// 读取服务端信息与能力。
  Future<ServerInfoDto> fetchServerInfo();

  /// 连通性探测。
  Future<void> ping();

  /// 读取服务端登录公钥（PEM 或裸 Base64 DER）。
  Future<String?> fetchPublicKey();

  /// 登录。
  ///
  /// 密码加密约定由具体实现负责：
  /// * Client API：`RSA(明文)`
  /// * 既有服务端：`RSA(MD5^5(明文))`
  ///
  /// 返回体包含令牌与（可能为空）用户信息，便于上层决定是否追加一次用户信息请求。
  Future<LoginResponseDto> login({
    required String username,
    required String password,
  });

  /// 刷新令牌。
  Future<TokenDto> refresh(String refreshToken);

  /// 登出。
  Future<void> logout(String accessToken);

  /// 校验当前会话是否有效。
  Future<void> validateSession(String accessToken);

  /// 读取当前用户信息。
  Future<UserDto> fetchProfile(String accessToken);

  /// 读取开屏配置（无需鉴权）。
  ///
  /// 服务端未提供该接口时返回「官方开屏」，由客户端使用本地品牌资源兜底。
  Future<SplashConfigDto> fetchSplash();

  /// 分页获取内容列表。
  Future<PageDto<ContentItemDto>> listContent(
    ContentKind kind, {
    String? cursor,
    int pageSize,
    String? keyword,
    String? category,
  });

  /// 读取内容详情。
  Future<ContentDetailDto> detail(ContentKind kind, String id);

  /// 读取章节列表。
  Future<List<ChapterDto>> chapters(ContentKind kind, String id);

  /// 读取小说章节正文（小说阅读器，文档 #39）。
  Future<ChapterContentDto> novelChapterContent(String bookId, String chapterId);

  /// 读取漫画章节图片（漫画阅读器，文档 #40）。
  Future<ComicChapterPagesDto> comicChapterPages(
    String albumId,
    String chapterId,
  );

  /// 读取服务端保存的阅读进度（跨设备续读，文档 #39 / #40）。
  ///
  /// 服务端未提供该接口、或该内容没有进度记录时返回 null，
  /// 客户端据此保持「本地进度优先」的行为。
  Future<ReadingProgressDto?> fetchReadingProgress(ContentKind kind, String id);

  /// 把阅读进度同步到服务端。
  ///
  /// 属于「尽力而为」的同步：服务端未提供接口时应静默忽略而不是抛异常，
  /// 避免影响本地阅读体验。
  Future<void> saveReadingProgress(ReadingProgress progress);

  /// 播放能力探测与决策（影视）。
  ///
  /// 把客户端解码能力上报给服务端，由服务端决定「直接播放 / 重封装 / 转码 /
  /// 不可播放」并给出播放地址。该接口**不产生副作用**，可以重复调用。
  ///
  /// 仅 Client API 方言支持；公开方言应返回
  /// [PlaybackDecisionDto.unsupported] 而不是抛异常。
  ///
  /// @param fileId     可播放文件标识（来自详情 `files`）
  /// @param capability 客户端能力上报（容器 / 编解码 / 最大码率等）
  Future<PlaybackDecisionDto> decidePlayback({
    required String fileId,
    required Map<String, Object?> capability,
  });
}
