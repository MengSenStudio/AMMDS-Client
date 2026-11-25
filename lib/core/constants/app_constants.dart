/// AMMDS 客户端全局常量。
///
/// 依据文档 #76「环境配置」与 #20「Client API 规范」，
/// 环境相关配置集中在此处，业务代码不得散落硬编码。
library;

/// 运行环境。
enum AppEnvironment {
  /// 开发环境。
  development,

  /// 预发布环境。
  staging,

  /// 生产环境。
  production,
}

/// 应用级常量。
abstract final class AppConstants {
  /// 应用标识，用于日志、User-Agent 与发现协议。
  static const String appId = 'ammds-client';

  /// 客户端版本号（与 pubspec version 保持一致）。
  static const String appVersion = '1.0.0';

  /// 客户端支持的 Client API 大版本。
  static const String supportedApiVersion = 'v1';

  /// 客户端支持的发现协议版本。
  static const int supportedDiscoveryVersion = 1;

  /// 公开发布入口（托盘菜单「官网」）。
  static const String websiteUrl = 'https://github.com/MengSenStudio/AMMDS-Docker/';

  /// 公开帮助文档（托盘菜单「帮助」）。
  static const String helpUrl = 'https://github.com/MengSenStudio/AMMDS-DOC/';

  /// 当前运行环境，可通过 `--dart-define=AMMDS_ENV=production` 覆盖。
  static AppEnvironment get environment => _environment;

  static final AppEnvironment _environment = _resolveEnvironment();

  /// 是否为生产环境。
  static bool get isProduction => environment == AppEnvironment.production;

  static AppEnvironment _resolveEnvironment() {
    const raw = String.fromEnvironment(
      'AMMDS_ENV',
      defaultValue: 'development',
    );
    return switch (raw) {
      'production' => AppEnvironment.production,
      'staging' => AppEnvironment.staging,
      _ => AppEnvironment.development,
    };
  }
}

/// Client API 路径常量（文档 #20 / #21 / #22）。
///
/// 客户端只依赖 `/api/client/v1/...`，与管理端 `/api/...` 逻辑隔离。
abstract final class ClientApiPaths {
  /// 统一前缀。
  static const String prefix = '/api/client/v1';

  /// 服务端信息 / 能力协商。
  static const String serverInfo = '$prefix/server/info';

  /// 连通性探测（无需鉴权）。
  static const String health = '$prefix/health';

  /// 开屏配置（无需鉴权）。
  static const String splash = '$prefix/splash';

  /// 登录。
  static const String login = '$prefix/auth/login';

  /// 刷新令牌。
  static const String refresh = '$prefix/auth/refresh';

  /// 登出。
  static const String logout = '$prefix/auth/logout';

  /// 校验当前会话。
  static const String session = '$prefix/auth/session';

  /// 当前用户信息。
  static const String profile = '$prefix/user/profile';

  /// 影视列表 / 搜索。
  static const String media = '$prefix/media';

  /// 影视可播放文件（播放流与播放决策以此为前缀）。
  static const String mediaFiles = '$prefix/media/files';

  /// 人物列表 / 搜索。
  static const String people = '$prefix/people';

  /// 小说列表 / 搜索。
  static const String novels = '$prefix/novels';

  /// 漫画列表 / 搜索。
  static const String comics = '$prefix/comics';

  /// 影视详情。
  static String mediaDetail(String id) => '$media/$id';

  /// 人物详情。
  static String peopleDetail(String id) => '$people/$id';

  /// 小说详情。
  static String novelDetail(String id) => '$novels/$id';

  /// 小说章节。
  static String novelChapters(String id) => '$novels/$id/chapters';

  /// 小说章节正文（阅读器）。
  static String novelChapterContent(String bookId, String chapterId) =>
      '$novels/$bookId/chapters/$chapterId';

  /// 漫画详情。
  static String comicDetail(String id) => '$comics/$id';

  /// 漫画章节。
  static String comicChapters(String id) => '$comics/$id/chapters';

  /// 漫画章节图片（阅读器）。
  static String comicChapterPages(String albumId, String chapterId) =>
      '$comics/$albumId/chapters/$chapterId';

  /// 小说阅读进度（GET 读取 / POST 保存）。
  static String novelProgress(String id) => '$novels/$id/progress';

  /// 漫画阅读进度（GET 读取 / POST 保存）。
  static String comicProgress(String id) => '$comics/$id/progress';
}

/// 网络超时策略（文档 #59）：不同用途使用不同超时。
abstract final class AppTimeouts {
  /// 建立连接超时。
  static const Duration connect = Duration(seconds: 10);

  /// 发送超时。
  static const Duration send = Duration(seconds: 15);

  /// 普通请求接收超时。
  static const Duration receive = Duration(seconds: 20);

  /// 搜索请求接收超时（搜索结果通常更慢）。
  static const Duration searchReceive = Duration(seconds: 30);

  /// 文件下载接收超时。
  static const Duration downloadReceive = Duration(minutes: 10);

  /// 图片请求接收超时。
  static const Duration imageReceive = Duration(seconds: 30);
}
