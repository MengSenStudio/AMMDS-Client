/// 阅读器领域模型（文档 #39 / #40）。
///
/// 阅读设置与阅读进度属于「用户偏好 / 本地状态」，
/// 与内容数据分离，避免与内容模型互相耦合。
library;

import 'content.dart';

/// 阅读背景配色。
enum ReaderBackground {
  /// 跟随浅色。
  light('light'),

  /// 护眼米黄。
  sepia('sepia'),

  /// 护眼绿。
  green('green'),

  /// 深色。
  dark('dark');

  const ReaderBackground(this.code);

  /// 持久化编码。
  final String code;

  /// 解析编码，未知时回落浅色。
  static ReaderBackground parse(String? raw) => switch (raw) {
    'sepia' => ReaderBackground.sepia,
    'green' => ReaderBackground.green,
    'dark' => ReaderBackground.dark,
    _ => ReaderBackground.light,
  };
}

/// 漫画阅读模式。
enum ComicReadMode {
  /// 翻页（单页横向翻页）。
  paged('paged'),

  /// 连续滚动（纵向长图）。
  continuous('continuous');

  const ComicReadMode(this.code);

  /// 持久化编码。
  final String code;

  /// 解析编码，未知时回落翻页模式。
  static ComicReadMode parse(String? raw) =>
      raw == 'continuous' ? ComicReadMode.continuous : ComicReadMode.paged;
}

/// 小说阅读模式。
enum NovelReadMode {
  /// 左右翻页（按版面分页，一次一屏）。
  paged('paged'),

  /// 纵向滚动。
  scroll('scroll');

  const NovelReadMode(this.code);

  /// 持久化编码。
  final String code;

  /// 解析编码，未知时回落翻页模式（与服务端网页阅读器的默认一致）。
  static NovelReadMode parse(String? raw) =>
      raw == 'scroll' ? NovelReadMode.scroll : NovelReadMode.paged;
}

/// 版心宽度档位（逻辑像素）。
enum ReaderContentWidth {
  /// 窄。
  narrow('narrow', 620),

  /// 适中。
  medium('medium', 760),

  /// 宽。
  wide('wide', 900);

  const ReaderContentWidth(this.code, this.maxWidth);

  /// 持久化编码。
  final String code;

  /// 版心最大宽度。
  final double maxWidth;

  /// 解析编码，未知时回落适中。
  static ReaderContentWidth parse(String? raw) => switch (raw) {
    'narrow' => ReaderContentWidth.narrow,
    'wide' => ReaderContentWidth.wide,
    _ => ReaderContentWidth.medium,
  };
}

/// 页边距档位（逻辑像素）。
enum ReaderPadding {
  /// 窄。
  narrow('narrow', 16),

  /// 适中。
  medium('medium', 30),

  /// 宽。
  wide('wide', 48);

  const ReaderPadding(this.code, this.value);

  /// 持久化编码。
  final String code;

  /// 左右页边距。
  final double value;

  /// 解析编码，未知时回落适中。
  static ReaderPadding parse(String? raw) => switch (raw) {
    'narrow' => ReaderPadding.narrow,
    'wide' => ReaderPadding.wide,
    _ => ReaderPadding.medium,
  };
}

/// 小说阅读设置。
final class NovelReaderSettings {
  /// 创建设置。
  const NovelReaderSettings({
    this.mode = NovelReadMode.paged,
    this.fontSize = 18,
    this.lineHeight = 1.8,
    this.contentWidth = ReaderContentWidth.medium,
    this.padding = ReaderPadding.medium,
    this.indentFirstLine = true,
    this.pageAnimation = true,
    this.autoNextChapter = true,
    this.background = ReaderBackground.light,
  });

  /// 最小字号。
  static const double minFontSize = 12;

  /// 最大字号。
  static const double maxFontSize = 34;

  /// 阅读模式。
  final NovelReadMode mode;

  /// 字号。
  final double fontSize;

  /// 行高倍数。
  final double lineHeight;

  /// 版心宽度档位。
  final ReaderContentWidth contentWidth;

  /// 页边距档位。
  final ReaderPadding padding;

  /// 首行缩进两字。
  final bool indentFirstLine;

  /// 翻页动画。
  final bool pageAnimation;

  /// 章末自动进入下一章。
  final bool autoNextChapter;

  /// 背景配色。
  final ReaderBackground background;

  /// 复制并覆盖部分字段。
  NovelReaderSettings copyWith({
    NovelReadMode? mode,
    double? fontSize,
    double? lineHeight,
    ReaderContentWidth? contentWidth,
    ReaderPadding? padding,
    bool? indentFirstLine,
    bool? pageAnimation,
    bool? autoNextChapter,
    ReaderBackground? background,
  }) => NovelReaderSettings(
    mode: mode ?? this.mode,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    contentWidth: contentWidth ?? this.contentWidth,
    padding: padding ?? this.padding,
    indentFirstLine: indentFirstLine ?? this.indentFirstLine,
    pageAnimation: pageAnimation ?? this.pageAnimation,
    autoNextChapter: autoNextChapter ?? this.autoNextChapter,
    background: background ?? this.background,
  );

  /// 转为存储用的 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.code,
    'font_size': fontSize,
    'line_height': lineHeight,
    'content_width': contentWidth.code,
    'padding': padding.code,
    'indent_first_line': indentFirstLine,
    'page_animation': pageAnimation,
    'auto_next_chapter': autoNextChapter,
    'background': background.code,
  };

  /// 从存储读取（缺失字段回落默认值，兼容旧版本数据）。
  static NovelReaderSettings fromJson(Map<String, Object?> json) =>
      NovelReaderSettings(
        mode: NovelReadMode.parse(json['mode'] as String?),
        fontSize: _double(json['font_size'], 18).clamp(minFontSize, maxFontSize),
        lineHeight: _double(json['line_height'], 1.8).clamp(1.2, 3.0),
        contentWidth: ReaderContentWidth.parse(json['content_width'] as String?),
        padding: ReaderPadding.parse(json['padding'] as String?),
        indentFirstLine: _bool(json['indent_first_line'], true),
        pageAnimation: _bool(json['page_animation'], true),
        autoNextChapter: _bool(json['auto_next_chapter'], true),
        background: ReaderBackground.parse(json['background'] as String?),
      );

  static double _double(Object? value, double fallback) => switch (value) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text) ?? fallback,
    _ => fallback,
  };

  static bool _bool(Object? value, bool fallback) => switch (value) {
    final bool flag => flag,
    final String text => text == 'true',
    _ => fallback,
  };
}

/// 漫画阅读设置。
final class ComicReaderSettings {
  /// 创建设置。
  const ComicReaderSettings({
    this.mode = ComicReadMode.paged,
    this.background = ReaderBackground.dark,
  });

  /// 阅读模式。
  final ComicReadMode mode;

  /// 背景配色（连续滚动模式下的页面底色）。
  final ReaderBackground background;

  /// 复制并覆盖部分字段。
  ComicReaderSettings copyWith({
    ComicReadMode? mode,
    ReaderBackground? background,
  }) => ComicReaderSettings(
    mode: mode ?? this.mode,
    background: background ?? this.background,
  );

  /// 转为存储用的 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.code,
    'background': background.code,
  };

  /// 从存储读取。
  static ComicReaderSettings fromJson(Map<String, Object?> json) =>
      ComicReaderSettings(
        mode: ComicReadMode.parse(json['mode'] as String?),
        background: ReaderBackground.parse(json['background'] as String?),
      );
}

/// 阅读进度。
final class ReadingProgress {
  /// 创建进度。
  const ReadingProgress({
    required this.kind,
    required this.id,
    required this.title,
    this.chapterId,
    this.chapterTitle,
    this.chapterIndex,
    this.page = 0,
    this.updatedAt,
  });

  /// 内容类型。
  final ContentKind kind;

  /// 内容 ID。
  final String id;

  /// 内容标题（列表展示用）。
  final String title;

  /// 章节 ID。
  final String? chapterId;

  /// 章节标题。
  final String? chapterTitle;

  /// 章节序号（从 1 开始）。
  final int? chapterIndex;

  /// 章节内进度（小说为滚动比例百分数，漫画为页序号）。
  final int page;

  /// 更新时间。
  final DateTime? updatedAt;

  /// 复制并覆盖部分字段。
  ReadingProgress copyWith({
    String? title,
    String? chapterId,
    String? chapterTitle,
    int? chapterIndex,
    int? page,
    DateTime? updatedAt,
  }) => ReadingProgress(
    kind: kind,
    id: id,
    title: title ?? this.title,
    chapterId: chapterId ?? this.chapterId,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    page: page ?? this.page,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// 转为存储用的 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.pathSegment,
    'id': id,
    'title': title,
    'chapter_id': chapterId,
    'chapter_title': chapterTitle,
    'chapter_index': chapterIndex,
    'page': page,
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  /// 从存储读取。
  static ReadingProgress? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final kindCode = json['kind'];
    final kind = switch (kindCode) {
      'media' => ContentKind.media,
      'people' => ContentKind.people,
      'comics' => ContentKind.comic,
      'novels' => ContentKind.novel,
      _ => null,
    };
    if (kind == null) {
      return null;
    }
    return ReadingProgress(
      kind: kind,
      id: id,
      title: json['title'] is String ? json['title']! as String : '',
      chapterId: json['chapter_id'] as String?,
      chapterTitle: json['chapter_title'] as String?,
      chapterIndex: switch (json['chapter_index']) {
        final int value => value,
        _ => null,
      },
      page: switch (json['page']) {
        final int value => value,
        _ => 0,
      },
      updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}'),
    );
  }
}
