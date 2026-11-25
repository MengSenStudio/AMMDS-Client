import 'package:ammds_client/app/app_container.dart';
import 'package:ammds_client/core/l10n/l10n.dart';
import 'package:ammds_client/core/storage/storage_impl.dart';
import 'package:ammds_client/core/theme/app_theme.dart';
import 'package:ammds_client/data/repositories/reading_repository_impl.dart';
import 'package:ammds_client/domain/entities/content.dart';
import 'package:ammds_client/domain/repositories/repositories.dart';
import 'package:ammds_client/features/media/presentation/pages/content_list_page.dart';
import 'package:ammds_client/shared/widgets/content_attributes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../test_support/test_app.dart';

/// 内容详情页组件测试（文档 #37 ~ #40）。
///
/// 四类内容共用同一详情页：验证扩展属性表、图集、人物关联作品与
/// 小说 / 漫画的章节目录、阅读入口是否按服务端数据渲染。
void main() {
  Future<void> pumpDetail(WidgetTester tester, ContentKind kind) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1600);
    addTearDown(tester.view.reset);
    TDTheme.needMultiTheme();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          contentRepositoryProvider.overrideWithValue(
            _FakeDetailRepository(kind),
          ),
          readingRepositoryProvider.overrideWithValue(
            ReadingRepositoryImpl(storage: InMemoryPreferencesStorage()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: TDTheme(
            data: TDTheme.defaultData(),
            systemData: AppTheme.light(),
            child: ContentDetailPage(
              kind: kind,
              id: '${kind.pathSegment}-1',
              title: '详情',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await settle(tester, frames: 8);
  }

  testWidgets('影视详情：展示扩展属性与图集', (tester) async {
    await pumpDetail(tester, ContentKind.media);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));

    expect(find.text('测试影片'), findsWidgets);
    expect(find.text(l10n.detailSectionInfo), findsOneWidget);
    expect(find.byType(ContentAttributes), findsOneWidget);
    expect(find.text(l10n.attrRuntime), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text(l10n.detailSectionGallery), findsOneWidget);
    expect(find.text(l10n.overview), findsOneWidget);
    // 不支持阅读器的类型不展示阅读入口
    expect(find.widgetWithText(TDButton, l10n.startReading), findsNothing);

    await drainTimers(tester);
  });

  testWidgets('人物详情：展示关联作品并可进入', (tester) async {
    await pumpDetail(tester, ContentKind.people);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));

    expect(find.text(l10n.detailSectionInfo), findsOneWidget);
    expect(find.text(l10n.attrHeight), findsOneWidget);
    expect(find.text(l10n.peopleRelatedContent), findsOneWidget);
    expect(find.text('参演影片'), findsWidgets);

    await drainTimers(tester);
  });

  testWidgets('小说详情：章节目录 + 阅读入口', (tester) async {
    await pumpDetail(tester, ContentKind.novel);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));

    expect(find.text(l10n.chapterList), findsOneWidget);
    expect(find.text('第 1 章'), findsWidgets);
    expect(find.text(l10n.attrPublisher), findsOneWidget);
    // 无阅读进度时展示「开始阅读」
    final start = find.widgetWithText(TDButton, l10n.startReading);
    expect(start, findsOneWidget);
    await tester.ensureVisible(start);
    await settle(tester, frames: 3);
    expect(start, findsOneWidget);

    await drainTimers(tester);
  });

  testWidgets('漫画详情：章节目录 + 阅读入口', (tester) async {
    await pumpDetail(tester, ContentKind.comic);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));

    expect(find.text(l10n.chapterList), findsOneWidget);
    expect(find.text(l10n.attrType), findsOneWidget);
    final start = find.widgetWithText(TDButton, l10n.startReading);
    await tester.ensureVisible(start);
    await settle(tester, frames: 3);
    expect(start, findsOneWidget);

    await drainTimers(tester);
  });
}

/// 假内容仓库：返回带有扩展属性 / 图集 / 关联作品 / 章节的详情。
final class _FakeDetailRepository implements ContentRepository {
  _FakeDetailRepository(this.kind);

  final ContentKind kind;

  static const List<ContentChapter> _chapters = <ContentChapter>[
    ContentChapter(id: 'chapter-1', title: '第 1 章', index: 1),
    ContentChapter(id: 'chapter-2', title: '第 2 章', index: 2),
  ];

  @override
  Future<PageResult<ContentItem>> list(
    ContentKind kind, {
    String? cursor,
    int pageSize = 20,
    String? keyword,
    String? category,
  }) async => PageResult.empty;

  @override
  Future<ContentDetail> detail(ContentKind kind, String id) async =>
      ContentDetail(
        item: ContentItem(
          id: id,
          title: _title,
          subtitle: '副标题',
          year: 2024,
          rating: 8.5,
          categories: const <String>['剧情'],
        ),
        overview: '详情简介',
        author: '作者甲',
        episodeCount: _chapters.length,
        chapters: kind == ContentKind.novel || kind == ContentKind.comic
            ? _chapters
            : const <ContentChapter>[],
        attributes: _attributes,
        gallery: <Uri>[Uri.parse('http://127.0.0.1:9/gallery/1.jpg')],
        related: kind == ContentKind.people
            ? <ContentItem>[
                const ContentItem(id: 'movie-1', title: '参演影片'),
              ]
            : const <ContentItem>[],
      );

  String get _title => switch (kind) {
    ContentKind.media => '测试影片',
    ContentKind.people => '测试人物',
    ContentKind.novel => '测试小说',
    ContentKind.comic => '测试漫画',
  };

  Map<String, String> get _attributes => switch (kind) {
    ContentKind.media => const <String, String>{
      'runtime_minutes': '120',
      'country': 'CN',
    },
    ContentKind.people => const <String, String>{
      'height_cm': '170',
      'blood_type': 'A',
    },
    ContentKind.novel => const <String, String>{
      'publisher': '出版社甲',
      'status': '连载中',
    },
    ContentKind.comic => const <String, String>{
      'type': '单行本',
      'season': '1',
    },
  };

  @override
  Future<List<ContentChapter>> chapters(ContentKind kind, String id) async =>
      _chapters;

  @override
  Future<ChapterContent> novelChapterContent(
    String bookId,
    String chapterId,
  ) async => const ChapterContent(
    id: 'chapter-1',
    title: '第 1 章',
    text: '正文',
    hasContent: true,
  );

  @override
  Future<ComicChapterPages> comicChapterPages(
    String albumId,
    String chapterId,
  ) async => const ComicChapterPages(
    chapterId: 'chapter-1',
    title: '第 1 话',
    pages: <ComicImage>[],
  );

  /// 播放决策：测试不使用播放能力，统一返回「不支持」。
  @override
  Future<PlaybackDecision> playbackDecision(String fileId) async =>
      PlaybackDecision.unsupported;
}
