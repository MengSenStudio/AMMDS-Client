import 'package:ammds_client/app/app_container.dart';
import 'package:ammds_client/core/l10n/l10n.dart';
import 'package:ammds_client/core/storage/storage_impl.dart';
import 'package:ammds_client/core/theme/app_theme.dart';
import 'package:ammds_client/data/repositories/reading_repository_impl.dart';
import 'package:ammds_client/domain/entities/content.dart';
import 'package:ammds_client/domain/entities/reading.dart';
import 'package:ammds_client/domain/repositories/repositories.dart';
import 'package:ammds_client/features/comic/presentation/pages/comic_reader_page.dart';
import 'package:ammds_client/features/novel/presentation/pages/novel_reader_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../test_support/test_app.dart';

/// 阅读器组件测试（文档 #39 / #40）。
///
/// 通过假内容仓库 + 真实阅读仓库（内存存储）驱动阅读器，
/// 验证「章节加载 / 章节切换 / 设置持久化 / 进度写入 / 漫画翻页」等交互，
/// 网络层由 `reader_dto_test` 与端到端用例覆盖。
void main() {
  group('小说阅读器', () {
    testWidgets('加载章节正文并按目录切换章节', (tester) async {
      final repository = _FakeContentRepository();
      final reading = ReadingRepositoryImpl(storage: InMemoryPreferencesStorage());

      await _pump(
        tester,
        repository: repository,
        reading: reading,
        child: const NovelReaderPage(bookId: 'n1'),
      );

      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
      // 无历史进度时从第一章开始
      expect(repository.novelRequests.single, 'n1|chapter-1');
      // 默认翻页模式：正文按段落分页渲染（每段一个 Text），首行带缩进前缀
      expect(find.textContaining('第 1 章正文第一段'), findsOneWidget);
      expect(find.textContaining('第 1 章正文第二段'), findsOneWidget);
      expect(find.text(l10n.readerChapterProgress(1, 3)), findsOneWidget);

      // 下一章（正文底部与底栏各有一个入口，取底栏按钮）
      await tester.tap(
        find.widgetWithText(TDButton, l10n.readerNextChapter).last,
      );
      await settle(tester);
      expect(repository.novelRequests.last, 'n1|chapter-2');
      expect(find.textContaining('第 2 章正文第一段'), findsOneWidget);

      // 进度已写入本地
      final progress = await reading.readProgress(ContentKind.novel, 'n1');
      expect(progress!.chapterId, 'chapter-2');
      expect(progress.chapterIndex, 2);

      await drainTimers(tester);
    });

    testWidgets('按历史进度恢复到上次章节', (tester) async {
      final repository = _FakeContentRepository();
      final reading = ReadingRepositoryImpl(storage: InMemoryPreferencesStorage());
      await reading.writeProgress(
        const ReadingProgress(
          kind: ContentKind.novel,
          id: 'n1',
          title: '三体',
          chapterId: 'chapter-3',
          chapterTitle: '第 3 章',
          chapterIndex: 3,
          page: 0,
        ),
      );

      await _pump(
        tester,
        repository: repository,
        reading: reading,
        child: const NovelReaderPage(bookId: 'n1'),
      );

      expect(repository.novelRequests.single, 'n1|chapter-3');

      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
      expect(find.text(l10n.readerChapterProgress(3, 3)), findsOneWidget);

      await drainTimers(tester);
    });

    testWidgets('阅读设置可调整并持久化', (tester) async {
      final repository = _FakeContentRepository();
      final reading = ReadingRepositoryImpl(storage: InMemoryPreferencesStorage());

      await _pump(
        tester,
        repository: repository,
        reading: reading,
        child: const NovelReaderPage(bookId: 'n1'),
      );

      // 打开设置弹层
      await tester.tap(find.byIcon(TDIcons.setting));
      await settle(tester, frames: 10);
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
      expect(find.text(l10n.readerSettings), findsOneWidget);

      final before = (await reading.readNovelSettings()).fontSize;
      await tester.tap(find.widgetWithText(TDButton, '+').first);
      await settle(tester, frames: 5);

      final after = await reading.readNovelSettings();
      expect(after.fontSize, before + 2);

      await drainTimers(tester);
    });
  });

  group('漫画阅读器', () {
    testWidgets('加载章节图片并显示页码', (tester) async {
      final repository = _FakeContentRepository();
      final reading = ReadingRepositoryImpl(storage: InMemoryPreferencesStorage());

      await _pump(
        tester,
        repository: repository,
        reading: reading,
        child: const ComicReaderPage(albumId: 'a1'),
      );

      expect(repository.comicRequests.single, 'a1|chapter-1');
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
      expect(find.text(l10n.comicPageProgress(1, 2)), findsOneWidget);

      // 章节切换
      await tester.tap(find.widgetWithText(TDButton, l10n.readerNextChapter));
      await settle(tester);
      expect(repository.comicRequests.last, 'a1|chapter-2');

      final progress = await reading.readProgress(ContentKind.comic, 'a1');
      expect(progress!.chapterId, 'chapter-2');
      expect(progress.page, 1);

      await drainTimers(tester);
    });

    testWidgets('可切换为连续滚动模式并持久化', (tester) async {
      final repository = _FakeContentRepository();
      final reading = ReadingRepositoryImpl(storage: InMemoryPreferencesStorage());

      await _pump(
        tester,
        repository: repository,
        reading: reading,
        child: const ComicReaderPage(albumId: 'a1'),
      );

      // 右上角「阅读模式」切换按钮
      await tester.tap(find.byIcon(TDIcons.menu));
      await settle(tester, frames: 5);

      final settings = await reading.readComicSettings();
      expect(settings.mode, ComicReadMode.continuous);

      await drainTimers(tester);
    });
  });
}

/// 装配被测阅读器（覆盖内容仓库与阅读仓库，使用内存存储）。
Future<void> _pump(
  WidgetTester tester, {
  required ContentRepository repository,
  required ReadingRepositoryImpl reading,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1400);
  addTearDown(tester.view.reset);
  TDTheme.needMultiTheme();

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        contentRepositoryProvider.overrideWithValue(repository),
        readingRepositoryProvider.overrideWithValue(reading),
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
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
  await settle(tester, frames: 8);
}

/// 假内容仓库：返回固定的书籍 / 相册、章节与正文。
final class _FakeContentRepository implements ContentRepository {
  /// 小说章节正文请求记录（`bookId|chapterId`）。
  final List<String> novelRequests = <String>[];

  /// 漫画章节图片请求记录（`albumId|chapterId`）。
  final List<String> comicRequests = <String>[];

  static const List<ContentChapter> _chapters = <ContentChapter>[
    ContentChapter(id: 'chapter-1', title: '第 1 章', index: 1),
    ContentChapter(id: 'chapter-2', title: '第 2 章', index: 2),
    ContentChapter(id: 'chapter-3', title: '第 3 章', index: 3),
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
  Future<ContentDetail> detail(ContentKind kind, String id) async => ContentDetail(
    item: ContentItem(id: id, title: kind == ContentKind.novel ? '三体' : '漫画'),
    overview: '简介',
    author: '作者甲',
    episodeCount: _chapters.length,
    chapters: _chapters,
  );

  @override
  Future<List<ContentChapter>> chapters(ContentKind kind, String id) async =>
      _chapters;

  @override
  Future<ChapterContent> novelChapterContent(
    String bookId,
    String chapterId,
  ) async {
    novelRequests.add('$bookId|$chapterId');
    final index = _indexOf(chapterId);
    return ChapterContent(
      id: chapterId,
      bookId: bookId,
      title: '第 $index 章',
      index: index,
      text: '第 $index 章正文第一段\n第 $index 章正文第二段',
      content: '<p>第 $index 章正文第一段</p><p>第 $index 章正文第二段</p>',
      wordCount: 16,
      hasContent: true,
      prevId: index > 1 ? 'chapter-${index - 1}' : null,
      nextId: index < _chapters.length ? 'chapter-${index + 1}' : null,
    );
  }

  @override
  Future<ComicChapterPages> comicChapterPages(
    String albumId,
    String chapterId,
  ) async {
    comicRequests.add('$albumId|$chapterId');
    final index = _indexOf(chapterId);
    return ComicChapterPages(
      chapterId: chapterId,
      title: '第 $index 话',
      albumId: albumId,
      index: index,
      pages: <ComicImage>[
        ComicImage(
          sequence: 1,
          imageUri: Uri.parse('http://127.0.0.1:9/pages/$index-1.png'),
        ),
        ComicImage(
          sequence: 2,
          imageUri: Uri.parse('http://127.0.0.1:9/pages/$index-2.png'),
        ),
      ],
      prevId: index > 1 ? 'chapter-${index - 1}' : null,
      nextId: index < _chapters.length ? 'chapter-${index + 1}' : null,
    );
  }

  static int _indexOf(String chapterId) =>
      int.tryParse(chapterId.split('-').last) ?? 1;

  /// 播放决策：阅读器用例不涉及播放，统一返回「不支持」。
  @override
  Future<PlaybackDecision> playbackDecision(String fileId) async =>
      PlaybackDecision.unsupported;
}
