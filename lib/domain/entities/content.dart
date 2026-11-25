/// 内容领域模型（文档 #37 ~ #40 / #69 / #73）。
library;

/// 统一分页模型（文档 #69）：UI 不感知服务端分页方式。
final class PageResult<T> {
  /// 创建分页结果。
  const PageResult({
    required this.items,
    required this.hasMore,
    this.nextCursor,
    this.page,
    this.total,
  });

  /// 空结果。
  static const PageResult<Never> empty = PageResult<Never>(
    items: <Never>[],
    hasMore: false,
  );

  /// 当前页数据。
  final List<T> items;

  /// 是否还有更多。
  final bool hasMore;

  /// 下一页游标。
  final String? nextCursor;

  /// 当前页码（页码分页时使用）。
  final int? page;

  /// 总条数（服务端提供时使用）。
  final int? total;

  /// 转换为另一个类型的分页结果（保持分页元信息）。
  PageResult<R> map<R>(R Function(T item) transform) => PageResult<R>(
    items: items.map(transform).toList(growable: false),
    hasMore: hasMore,
    nextCursor: nextCursor,
    page: page,
    total: total,
  );
}

/// 分页请求参数。
final class PageQuery {
  /// 创建查询参数。
  const PageQuery({this.cursor, this.page, this.pageSize = 20, this.keyword});

  /// 游标分页参数。
  final String? cursor;

  /// 页码分页参数。
  final int? page;

  /// 每页数量。
  final int pageSize;

  /// 关键词。
  final String? keyword;

  /// 组装查询串。
  Map<String, Object?> toQueryParameters() => <String, Object?>{
    if (cursor != null) 'cursor': cursor,
    if (page != null) 'page': page,
    'page_size': pageSize,
    if (keyword != null && keyword!.isNotEmpty) 'keyword': keyword,
  };
}

/// 内容条目通用模型。
///
/// 影视 / 人物 / 小说 / 漫画 在客户端列表中展示的字段高度一致，
/// 统一为 [ContentItem]，避免在 UI 层区分四种几乎相同的模型。
final class ContentItem {
  /// 创建内容条目。
  const ContentItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.coverUri,
    this.coverFallbackUri,
    this.year,
    this.rating,
    this.categories = const <String>[],
    this.extra = const <String, Object?>{},
  });

  /// 唯一标识。
  final String id;

  /// 标题。
  final String title;

  /// 副标题（作者、地区等）。
  final String? subtitle;

  /// 封面地址。
  final Uri? coverUri;

  /// 封面直连地址（服务端代理失败时的回退）。
  ///
  /// 远端封面一律经服务端代理下发，但服务端可能取不到图——典型情况是图床在服务端
  /// 所在网络被屏蔽、而手机能访问。此时客户端直连原地址仍能显示封面，
  /// 因此这里保留一份未经代理的地址供 [AppImage] 回退。
  /// 仓库内的相对路径没有可直连的地址，此时为 null。
  final Uri? coverFallbackUri;

  /// 年份。
  final int? year;

  /// 评分。
  final double? rating;

  /// 分类 / 类型标签。
  final List<String> categories;

  /// 其他原始字段，供详情页按需使用。
  final Map<String, Object?> extra;

  @override
  String toString() => 'ContentItem($id, $title)';
}

/// 影视可播放文件（服务端下发的播放资源）。
///
/// 一部影视可能对应多个文件：不同分集 / 片段，或同一影片散落在多个目录。
/// 服务端只下发 `fileId` 等元信息（不下发服务器绝对路径），
/// 真正的播放地址由播放决策接口按 `fileId` 给出。
final class MediaFile {
  /// 创建文件条目。
  const MediaFile({
    required this.id,
    required this.name,
    this.size,
    this.resolution,
    this.episodeIndex,
    this.partIndex,
    this.partTitle,
    this.available = true,
    this.source,
  });

  /// 文件标识（播放与探测接口使用）。
  final String id;

  /// 文件名。
  final String name;

  /// 文件大小（字节）。
  final int? size;

  /// 分辨率。
  final String? resolution;

  /// 分集 / 片段序号。
  final int? episodeIndex;

  /// 同一分集内的片段序号。
  final int? partIndex;

  /// 分集标题。
  final String? partTitle;

  /// 文件当前是否可用（文件可能被移动或删除，属于正常情况）。
  final bool available;

  /// 绑定来源（SCRAPE / MANUAL / SCAN）。
  final String? source;

  /// 展示用标题：优先「分集标题」，其次「第 N 集」，最后回落文件名。
  String get displayTitle {
    final title = partTitle;
    if (title != null && title.isNotEmpty) {
      return title;
    }
    final episode = episodeIndex;
    if (episode != null && episode > 1) {
      return 'EP$episode · $name';
    }
    return name;
  }
}

/// 播放方式（服务端决策结果）。
enum PlaybackMode {
  /// 直接播放。
  direct('direct'),

  /// 需要重封装容器。
  remux('remux'),

  /// 需要转码。
  transcode('transcode'),

  /// 当前服务端/客户端不具备播放条件。
  unsupported('unsupported');

  const PlaybackMode(this.code);

  /// 服务端编码。
  final String code;

  /// 解析编码，未知时按不支持处理（宁可提示原因，也不要「假装能播」）。
  static PlaybackMode parse(String? raw) => switch (raw) {
    'direct' => PlaybackMode.direct,
    'remux' => PlaybackMode.remux,
    'transcode' => PlaybackMode.transcode,
    _ => PlaybackMode.unsupported,
  };

  /// 是否可以直接播放（含仅需重封装以外的可播情形）。
  bool get isPlayable => this == PlaybackMode.direct || this == PlaybackMode.remux;
}

/// 播放决策。
final class PlaybackDecision {
  /// 创建决策。
  const PlaybackDecision({
    required this.mode,
    this.url,
    this.mimeType,
    this.reason,
    this.targetBitrate,
  });

  /// 播放方式。
  final PlaybackMode mode;

  /// 播放地址（相对服务端根路径）。
  final String? url;

  /// 内容类型。
  final String? mimeType;

  /// 决策说明（不可播放时为原因）。
  final String? reason;

  /// 建议码率（转码时给出）。
  final int? targetBitrate;

  /// 不可播放的降级决策。
  static const PlaybackDecision unsupported = PlaybackDecision(
    mode: PlaybackMode.unsupported,
  );
}

/// 内容详情。
final class ContentDetail {
  /// 创建内容详情。
  const ContentDetail({
    required this.item,
    this.overview,
    this.episodeCount,
    this.status,
    this.author,
    this.chapters = const <ContentChapter>[],
    this.related = const <ContentItem>[],
    this.attributes = const <String, String>{},
    this.gallery = const <Uri>[],
    this.files = const <MediaFile>[],
  });

  /// 基础条目。
  final ContentItem item;

  /// 简介。
  final String? overview;

  /// 集数 / 章节数。
  final int? episodeCount;

  /// 状态。
  final String? status;

  /// 作者（小说、漫画）。
  final String? author;

  /// 章节列表（小说、漫画）。
  final List<ContentChapter> chapters;

  /// 关联内容（人物关联影视等）。
  final List<ContentItem> related;

  /// 扩展属性（人物的身高 / 血型、影视的语言 / 分辨率等）。
  ///
  /// 键为服务端约定的英文键名，UI 层按需映射为本地化标签；
  /// 服务端新增字段时客户端无需发版即可展示。
  final Map<String, String> attributes;

  /// 图集（海报 / 剧照 / 写真）。
  final List<Uri> gallery;

  /// 可播放文件（影视；其它内容类型为空）。
  ///
  /// 服务端会为新旧数据统一适配出一份可播放清单，因此这里可能同时包含
  /// 「新实体记录」与「由既有绑定兜底合成」的条目。
  final List<MediaFile> files;

  /// 内容条目。
  ContentItem get summary => item;
}

/// 章节。
final class ContentChapter {
  /// 创建章节。
  const ContentChapter({required this.id, required this.title, this.index});

  /// 章节标识。
  final String id;

  /// 章节标题。
  final String title;

  /// 序号。
  final int? index;

  @override
  String toString() => 'ContentChapter($id, $title)';
}

/// 小说章节正文（小说阅读器的数据来源）。
final class ChapterContent {
  /// 创建章节正文。
  const ChapterContent({
    required this.id,
    required this.title,
    this.bookId,
    this.index,
    this.text,
    this.content,
    this.wordCount,
    this.hasContent = false,
    this.fromSource = false,
    this.prevId,
    this.nextId,
  });

  /// 章节标识。
  final String id;

  /// 章节标题。
  final String title;

  /// 所属书籍标识。
  final String? bookId;

  /// 章节序号（服务端按目录顺序给出，从 1 开始）。
  final int? index;

  /// 纯文本正文（客户端阅读器渲染的内容）。
  final String? text;

  /// 原始正文（可能包含 HTML）。
  final String? content;

  /// 字数。
  final int? wordCount;

  /// 是否存在可阅读正文。
  final bool hasContent;

  /// 是否为书源章节（正文按需抓取）。
  final bool fromSource;

  /// 上一章标识。
  final String? prevId;

  /// 下一章标识。
  final String? nextId;

  @override
  String toString() => 'ChapterContent($id, $title)';
}

/// 漫画图片页。
///
/// 命名避免与漫画模块页面组件 `ComicPage` 冲突。
final class ComicImage {
  /// 创建漫画页。
  const ComicImage({required this.sequence, required this.imageUri});

  /// 页序号（从 1 开始）。
  final int sequence;

  /// 图片地址。
  final Uri imageUri;

  @override
  String toString() => 'ComicImage($sequence)';
}

/// 漫画章节图片（漫画阅读器的数据来源）。
final class ComicChapterPages {
  /// 创建章节图片集合。
  const ComicChapterPages({
    required this.chapterId,
    required this.title,
    this.albumId,
    this.index,
    this.pages = const <ComicImage>[],
    this.prevId,
    this.nextId,
  });

  /// 章节标识。
  final String chapterId;

  /// 章节标题。
  final String title;

  /// 所属相册标识。
  final String? albumId;

  /// 章节序号（从 1 开始）。
  final int? index;

  /// 图片页（按阅读顺序）。
  final List<ComicImage> pages;

  /// 上一章标识。
  final String? prevId;

  /// 下一章标识。
  final String? nextId;

  /// 页数。
  int get pageCount => pages.length;

  @override
  String toString() => 'ComicChapterPages($chapterId, ${pages.length})';
}

/// 内容模块类型（影视 / 人物 / 小说 / 漫画）。
enum ContentKind {
  /// 影视。
  media('media'),

  /// 人物。
  people('people'),

  /// 小说。
  novel('novels'),

  /// 漫画。
  comic('comics');

  const ContentKind(this.pathSegment);

  /// 在 Client API 中使用的路径片段。
  final String pathSegment;
}
