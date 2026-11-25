import '../entities/auth.dart';
import '../entities/content.dart';
import '../entities/promote.dart';
import '../entities/reading.dart';
import '../entities/server.dart';
import '../entities/splash.dart';

/// 认证仓库接口（文档 #19 / #23 / #26）。
abstract interface class AuthRepository {
  /// 登录。
  Future<AuthResult> login({
    required ServerProfile server,
    required AuthCredentials credentials,
  });

  /// 刷新令牌。
  Future<AuthTokens> refresh({
    required ServerProfile server,
    required String refreshToken,
  });

  /// 登出。
  Future<void> logout({
    required ServerProfile server,
    required String accessToken,
  });

  /// 拉取当前用户信息（用于启动时的会话有效性校验，文档 #54）。
  Future<UserProfile> fetchProfile({
    required ServerProfile server,
    required String accessToken,
  });

  /// 校验会话是否仍然有效。
  Future<bool> validateSession({
    required ServerProfile server,
    required String accessToken,
  });
}

/// 服务端仓库接口（文档 #90）。
abstract interface class ServerRepository {
  /// 局域网发现（UDP 广播 / 多播，文档 #16）。
  Future<List<ServerProfile>> discover({
    void Function(ServerProfile server)? onServerFound,
  });

  /// 测试连接并读取服务端信息（文档 #18 / #81）。
  Future<ServerProfile> probe(ServerProfile candidate);

  /// 读取服务端信息与能力（文档 #82）。
  Future<ServerProfile> fetchServerInfo(ServerProfile server);

  /// 读取指定服务端的开屏配置（文档 #14）。
  ///
  /// 无论服务端是否可达都必须返回可用配置：失败或未配置时回落到本地官方开屏，
  /// 因此调用方（开屏页）无需处理异常分支。
  Future<SplashConfig> fetchSplashConfig(
    ServerProfile server, {
    required String fallbackProductName,
    required String fallbackCopyright,
  });
}

/// 内容仓库接口（文档 #71）。
///
/// UI / Controller 只依赖该接口，不感知 HTTP 与 DTO。
abstract interface class ContentRepository {
  /// 分页获取内容列表。
  Future<PageResult<ContentItem>> list(
    ContentKind kind, {
    String? cursor,
    int pageSize = 20,
    String? keyword,
    String? category,
  });

  /// 获取内容详情。
  Future<ContentDetail> detail(ContentKind kind, String id);

  /// 获取章节列表（小说 / 漫画）。
  Future<List<ContentChapter>> chapters(ContentKind kind, String id);

  /// 获取小说章节正文（小说阅读器，文档 #39）。
  Future<ChapterContent> novelChapterContent(String bookId, String chapterId);

  /// 获取漫画章节图片（漫画阅读器，文档 #40）。
  Future<ComicChapterPages> comicChapterPages(
    String albumId,
    String chapterId,
  );

  /// 播放能力探测与决策（影视）。
  ///
  /// 客户端能力由实现内部按当前平台探测后上报，UI 无需关心平台差异。
  /// 返回的 [PlaybackDecision.url] 已是可直接访问的绝对地址
  /// （但仍需由调用方附加访问令牌，见 `MediaPlayerPage`）。
  Future<PlaybackDecision> playbackDecision(String fileId);
}

/// 阅读仓库接口（文档 #39 / #40：阅读进度与阅读设置）。
///
/// 阅读设置与进度保存在本地普通配置中：设置项属于「用户偏好」，
/// 进度即使在离线状态下也必须可用，因此不依赖服务端接口。
abstract interface class ReadingRepository {
  /// 读取小说阅读设置。
  Future<NovelReaderSettings> readNovelSettings();

  /// 写入小说阅读设置。
  Future<void> writeNovelSettings(NovelReaderSettings settings);

  /// 读取漫画阅读设置。
  Future<ComicReaderSettings> readComicSettings();

  /// 写入漫画阅读设置。
  Future<void> writeComicSettings(ComicReaderSettings settings);

  /// 读取指定内容的阅读进度。
  Future<ReadingProgress?> readProgress(ContentKind kind, String id);

  /// 写入阅读进度。
  Future<void> writeProgress(ReadingProgress progress);

  /// 读取最近阅读记录（按更新时间倒序）。
  Future<List<ReadingProgress>> readRecentProgress({int limit = 20});
}

/// 阅读进度的服务端通道（文档 #39 / #40：跨设备续读）。
///
/// 与 [ReadingRepository] 分开定义，让本地仓库保持「离线优先」：
/// 本地存储始终是阅读进度的第一来源，服务端只用于跨设备对齐。
/// 服务端未提供进度接口时，装配层不注入该通道，此时退化为纯本地进度。
abstract interface class ReadingProgressRemote {
  /// 读取服务端保存的进度；无记录或接口不可用时返回 null。
  Future<ReadingProgress?> fetch(ContentKind kind, String id);

  /// 保存进度到服务端。
  Future<void> save(ReadingProgress progress);
}

/// 官方推送通告仓库。
///
/// 数据来自**官方远端 JSON**（与网页端 `app/src/utils/promote.ts` 同一地址），
/// 不是 AMMDS 服务端的系统通知（那是后台消息中心的数据，用途完全不同）。
///
/// 「已读」采用**当日已读**语义，只记录在本地，不回写任何远端状态。
abstract interface class PromoteRepository {
  /// 拉取通告列表：远端优先，失败回落本地缓存，都没有则为空列表。
  Future<List<AppPromote>> load();

  /// 处于推送窗口内、且当日未读的通告（保持源顺序）。
  Future<List<AppPromote>> pending({DateTime? now});

  /// 把通告标记为「当日已读」。
  Future<void> markRead(String id, {DateTime? now});
}

/// 设置仓库接口（文档 #42 / #43）。
abstract interface class SettingsRepository {
  /// 读取主题模式。
  Future<String?> readThemeMode();

  /// 写入主题模式。
  Future<void> writeThemeMode(String value);

  /// 读取语言代码。
  Future<String?> readLocale();

  /// 写入语言代码。
  Future<void> writeLocale(String value);

  /// 读取已保存的服务端档案。
  Future<List<ServerProfile>> readServerProfiles();

  /// 保存服务端档案列表。
  Future<void> saveServerProfiles(List<ServerProfile> profiles);

  /// 读取当前服务端 ID。
  Future<String?> readActiveServerId();

  /// 写入当前服务端 ID。
  Future<void> writeActiveServerId(String? serverId);
}
