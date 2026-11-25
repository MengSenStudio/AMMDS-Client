/// 路由路径常量（文档 #12）。
abstract final class RoutePaths {
  /// 开屏。
  static const String splash = '/splash';

  /// 登录。
  static const String login = '/login';

  /// 服务端发现 / 选择。
  static const String deviceDiscovery = '/device-discovery';

  /// 主界面根路径。
  static const String mainRoot = '/main';

  /// 影视。
  static const String media = '/main/media';

  /// 人物。
  static const String people = '/main/people';

  /// 小说。
  static const String novel = '/main/novel';

  /// 漫画。
  static const String comic = '/main/comic';

  /// 管理（个人信息 / 服务器 / 应用配置 / 关于）。
  static const String management = '/main/management';

  /// 各模块详情路由。
  static String mediaDetail(String id) => '$media/detail?id=$id';

  /// 影视播放页。
  ///
  /// 播放所需的数据量较大（可播放文件清单），不适合放进地址栏，
  /// 因此通过 go_router 的 `extra` 传递（见 `MediaPlayerArgs`）。
  static const String mediaPlayer = '$media/player';

  /// 人物详情。
  static String peopleDetail(String id) => '$people/detail?id=$id';

  /// 小说详情。
  static String novelDetail(String id) => '$novel/detail?id=$id';

  /// 漫画详情。
  static String comicDetail(String id) => '$comic/detail?id=$id';

  /// 小说阅读器（文档 #39）。
  static String novelReader(String bookId, {String? chapterId}) {
    final base = '$novel/detail/read?bookId=${Uri.encodeQueryComponent(bookId)}';
    if (chapterId == null || chapterId.isEmpty) {
      return base;
    }
    return '$base&chapterId=${Uri.encodeQueryComponent(chapterId)}';
  }

  /// 漫画阅读器（文档 #40）。
  static String comicReader(String albumId, {String? chapterId}) {
    final base =
        '$comic/detail/read?albumId=${Uri.encodeQueryComponent(albumId)}';
    if (chapterId == null || chapterId.isEmpty) {
      return base;
    }
    return '$base&chapterId=${Uri.encodeQueryComponent(chapterId)}';
  }
}
