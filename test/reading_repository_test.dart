import 'package:ammds_client/core/storage/storage.dart';
import 'package:ammds_client/core/storage/storage_impl.dart';
import 'package:ammds_client/data/repositories/reading_repository_impl.dart';
import 'package:ammds_client/domain/entities/content.dart';
import 'package:ammds_client/domain/entities/reading.dart';
import 'package:ammds_client/domain/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryPreferencesStorage storage;
  late ReadingRepositoryImpl repository;

  setUp(() {
    storage = InMemoryPreferencesStorage();
    repository = ReadingRepositoryImpl(storage: storage);
  });

  group('阅读设置', () {
    test('默认设置', () async {
      final novel = await repository.readNovelSettings();
      expect(novel.fontSize, 18);
      expect(novel.lineHeight, 1.8);
      expect(novel.background, ReaderBackground.light);

      final comic = await repository.readComicSettings();
      expect(comic.mode, ComicReadMode.paged);
      expect(comic.background, ReaderBackground.dark);
    });

    test('小说设置可持久化并回读', () async {
      await repository.writeNovelSettings(
        const NovelReaderSettings(
          fontSize: 24,
          lineHeight: 2.2,
          background: ReaderBackground.sepia,
        ),
      );
      final restored = await repository.readNovelSettings();
      expect(restored.fontSize, 24);
      expect(restored.lineHeight, 2.2);
      expect(restored.background, ReaderBackground.sepia);
      expect(
        await storage.readString(StorageKeys.novelReaderSettings),
        contains('sepia'),
      );
    });

    test('漫画设置可持久化并回读', () async {
      await repository.writeComicSettings(
        const ComicReaderSettings(
          mode: ComicReadMode.continuous,
          background: ReaderBackground.light,
        ),
      );
      final restored = await repository.readComicSettings();
      expect(restored.mode, ComicReadMode.continuous);
      expect(restored.background, ReaderBackground.light);
    });

    test('设置值越界时收敛到合法区间', () async {
      await storage.writeString(
        StorageKeys.novelReaderSettings,
        '{"font_size": 200, "line_height": 9, "background": "unknown"}',
      );
      final restored = await repository.readNovelSettings();
      expect(restored.fontSize, NovelReaderSettings.maxFontSize);
      expect(restored.lineHeight, 3.0);
      expect(restored.background, ReaderBackground.light);
    });

    test('存储内容损坏时回落到默认设置', () async {
      await storage.writeString(StorageKeys.novelReaderSettings, 'not-json');
      expect((await repository.readNovelSettings()).fontSize, 18);
    });
  });

  group('阅读进度', () {
    test('写入后可按内容维度读取', () async {
      await repository.writeProgress(
        const ReadingProgress(
          kind: ContentKind.novel,
          id: 'n1',
          title: '三体',
          chapterId: 'c2',
          chapterTitle: '第二章',
          chapterIndex: 2,
          page: 40,
        ),
      );

      final progress = await repository.readProgress(ContentKind.novel, 'n1');
      expect(progress, isNotNull);
      expect(progress!.chapterId, 'c2');
      expect(progress.chapterTitle, '第二章');
      expect(progress.chapterIndex, 2);
      expect(progress.page, 40);
      expect(progress.updatedAt, isNotNull);

      // 不同内容类型互不影响
      expect(await repository.readProgress(ContentKind.comic, 'n1'), isNull);
      expect(await repository.readProgress(ContentKind.novel, 'n2'), isNull);
    });

    test('同一内容重复写入只保留最新进度', () async {
      await repository.writeProgress(
        const ReadingProgress(
          kind: ContentKind.comic,
          id: 'a1',
          title: '漫画',
          chapterId: 'cc1',
          page: 1,
        ),
      );
      await repository.writeProgress(
        const ReadingProgress(
          kind: ContentKind.comic,
          id: 'a1',
          title: '漫画',
          chapterId: 'cc2',
          page: 5,
        ),
      );
      final progress = await repository.readProgress(ContentKind.comic, 'a1');
      expect(progress!.chapterId, 'cc2');
      expect(progress.page, 5);
    });

    test('最近阅读按更新时间倒序', () async {
      await repository.writeProgress(
        ReadingProgress(
          kind: ContentKind.novel,
          id: 'n1',
          title: '小说一',
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      await repository.writeProgress(
        ReadingProgress(
          kind: ContentKind.comic,
          id: 'a1',
          title: '漫画一',
          updatedAt: DateTime(2026, 5, 1),
        ),
      );

      final recent = await repository.readRecentProgress();
      expect(recent.length, 2);
      expect(recent.first.id, 'a1');
      expect(recent.last.id, 'n1');
    });

    test('存储内容损坏时返回空进度而不抛异常', () async {
      await storage.writeString(StorageKeys.readingProgress, '{bad json');
      expect(await repository.readRecentProgress(), isEmpty);
      expect(await repository.readProgress(ContentKind.novel, 'n1'), isNull);
    });
  });

  group('阅读进度服务端同步', () {
    late _FakeProgressRemote remote;

    setUp(() {
      remote = _FakeProgressRemote();
      repository = ReadingRepositoryImpl(storage: storage, remote: remote);
    });

    test('本地无记录时采用服务端进度（新设备续读）', () async {
      remote.progress = ReadingProgress(
        kind: ContentKind.novel,
        id: 'n1',
        title: '三体',
        chapterId: 'c8',
        chapterTitle: '第八章',
        chapterIndex: 8,
        page: 30,
        updatedAt: DateTime(2026, 5, 1),
      );

      final progress = await repository.readProgress(ContentKind.novel, 'n1');
      expect(progress!.chapterId, 'c8');
      expect(progress.page, 30);
      // 已回写本地缓存，后续离线读取仍可续读
      remote.progress = null;
      expect(
        (await repository.readProgress(ContentKind.novel, 'n1'))!.chapterId,
        'c8',
      );
    });

    test('服务端进度更新时覆盖本地', () async {
      await repository.writeProgress(
        ReadingProgress(
          kind: ContentKind.novel,
          id: 'n1',
          title: '三体',
          chapterId: 'c2',
          page: 10,
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      remote.progress = ReadingProgress(
        kind: ContentKind.novel,
        id: 'n1',
        title: '三体',
        chapterId: 'c9',
        page: 80,
        updatedAt: DateTime(2026, 6, 1),
      );

      final progress = await repository.readProgress(ContentKind.novel, 'n1');
      expect(progress!.chapterId, 'c9');
      expect(progress.page, 80);
    });

    test('服务端进度更旧时保留本地', () async {
      await repository.writeProgress(
        ReadingProgress(
          kind: ContentKind.novel,
          id: 'n1',
          title: '三体',
          chapterId: 'c9',
          page: 80,
          updatedAt: DateTime(2026, 6, 1),
        ),
      );
      remote.progress = ReadingProgress(
        kind: ContentKind.novel,
        id: 'n1',
        title: '三体',
        chapterId: 'c1',
        page: 0,
        updatedAt: DateTime(2026, 1, 1),
      );

      final progress = await repository.readProgress(ContentKind.novel, 'n1');
      expect(progress!.chapterId, 'c9');
    });

    test('服务端进度缺少时间时不覆盖本地', () async {
      await repository.writeProgress(
        ReadingProgress(
          kind: ContentKind.comic,
          id: 'a1',
          title: '漫画',
          chapterId: 'cc2',
          page: 5,
          updatedAt: DateTime(2026, 6, 1),
        ),
      );
      remote.progress = const ReadingProgress(
        kind: ContentKind.comic,
        id: 'a1',
        title: '漫画',
        chapterId: 'cc1',
        page: 1,
      );

      final progress = await repository.readProgress(ContentKind.comic, 'a1');
      expect(progress!.chapterId, 'cc2');
    });

    test('写入本地后同步到服务端', () async {
      await repository.writeProgress(
        const ReadingProgress(
          kind: ContentKind.comic,
          id: 'a1',
          title: '漫画',
          chapterId: 'cc2',
          page: 7,
        ),
      );

      expect(remote.saved.length, 1);
      expect(remote.saved.single.id, 'a1');
      expect(remote.saved.single.page, 7);
    });

    test('服务端读取失败时回退本地', () async {
      remote.fetchError = Exception('network down');
      await repository.writeProgress(
        const ReadingProgress(
          kind: ContentKind.novel,
          id: 'n1',
          title: '三体',
          chapterId: 'c3',
          page: 20,
        ),
      );

      final progress = await repository.readProgress(ContentKind.novel, 'n1');
      expect(progress!.chapterId, 'c3');
    });
  });
}

/// 假的服务端进度通道：记录保存调用并可注入读取结果 / 异常。
final class _FakeProgressRemote implements ReadingProgressRemote {
  /// 读取返回的进度。
  ReadingProgress? progress;

  /// 读取时抛出的异常。
  Object? fetchError;

  /// 已保存的进度。
  final List<ReadingProgress> saved = <ReadingProgress>[];

  @override
  Future<ReadingProgress?> fetch(ContentKind kind, String id) async {
    final error = fetchError;
    if (error != null) {
      throw error;
    }
    return progress;
  }

  @override
  Future<void> save(ReadingProgress progress) async {
    saved.add(progress);
  }
}
