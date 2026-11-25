import 'dart:async';
import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../core/storage/storage.dart';
import '../../domain/entities/content.dart';
import '../../domain/entities/reading.dart';
import '../../domain/repositories/repositories.dart';

/// 阅读仓库实现（文档 #39 / #40 / #43）。
///
/// 设置与进度都写在普通配置存储中：
/// * 阅读设置是用户偏好，需长期保留；
/// * 阅读进度需要离线可用，且不涉及敏感信息，因此不进入安全存储。
///
/// 进度以「内容类型 + 内容 ID」为键保存在单个 JSON 对象里，
/// 读取最近阅读记录时无需遍历全部键。
///
/// 服务端同步（[remote]）遵循**离线优先 + 后写者胜**：
/// * 读取：本地与服务端都取，取更新时间较新的一条，并回写本地缓存；
/// * 写入：本地立即生效，服务端同步「尽力而为」，失败不影响阅读。
final class ReadingRepositoryImpl implements ReadingRepository {
  /// 创建实现。
  ReadingRepositoryImpl({required this.storage, this.remote});

  /// 普通配置存储。
  final PreferencesStorage storage;

  /// 服务端进度通道；为空时退化为纯本地进度（离线或服务端未提供接口）。
  final ReadingProgressRemote? remote;

  /// 最近阅读记录保留上限（避免配置文件无限增长）。
  static const int _maxEntries = 60;

  @override
  Future<NovelReaderSettings> readNovelSettings() async {
    final json = await _readJson(StorageKeys.novelReaderSettings);
    return json == null
        ? const NovelReaderSettings()
        : NovelReaderSettings.fromJson(json);
  }

  @override
  Future<void> writeNovelSettings(NovelReaderSettings settings) => storage
      .writeString(StorageKeys.novelReaderSettings, jsonEncode(settings.toJson()));

  @override
  Future<ComicReaderSettings> readComicSettings() async {
    final json = await _readJson(StorageKeys.comicReaderSettings);
    return json == null
        ? const ComicReaderSettings()
        : ComicReaderSettings.fromJson(json);
  }

  @override
  Future<void> writeComicSettings(ComicReaderSettings settings) => storage
      .writeString(StorageKeys.comicReaderSettings, jsonEncode(settings.toJson()));

  @override
  Future<ReadingProgress?> readProgress(ContentKind kind, String id) async {
    final local = await _readLocalProgress(kind, id);
    final remoteProgress = await _fetchRemoteProgress(kind, id);
    if (remoteProgress == null) {
      return local;
    }
    if (local == null) {
      // 本地没有记录（新设备 / 首次打开）→ 直接采用服务端进度
      await _writeLocalProgress(remoteProgress);
      return remoteProgress;
    }
    if (_isNewer(remoteProgress, local)) {
      await _writeLocalProgress(remoteProgress);
      return remoteProgress;
    }
    return local;
  }

  @override
  Future<void> writeProgress(ReadingProgress progress) async {
    await _writeLocalProgress(progress);
    final channel = remote;
    if (channel == null) {
      return;
    }
    // 同步属于「尽力而为」：不阻塞调用方（阅读器连续滚动会高频写入），
    // 失败也只记录日志，不影响本地阅读。
    unawaited(
      channel.save(progress).catchError((Object error) {
        AppLogger.debug(
          'ReadingRepositoryImpl',
          'failed to sync reading progress: ${AppLogger.sanitize('$error')}',
        );
      }),
    );
  }

  /// 读取本地进度（不做任何服务端交互）。
  Future<ReadingProgress?> _readLocalProgress(
    ContentKind kind,
    String id,
  ) async {
    final entries = await _readEntries();
    return entries[_key(kind, id)];
  }

  /// 读取服务端进度；未配置通道或请求失败时返回 null。
  Future<ReadingProgress?> _fetchRemoteProgress(
    ContentKind kind,
    String id,
  ) async {
    final channel = remote;
    if (channel == null) {
      return null;
    }
    try {
      return await channel.fetch(kind, id);
    } on Object catch (error) {
      AppLogger.debug(
        'ReadingRepositoryImpl',
        'failed to fetch remote reading progress: '
            '${AppLogger.sanitize('$error')}',
      );
      return null;
    }
  }

  /// 写入本地进度（含容量裁剪与时间戳补全）。
  Future<void> _writeLocalProgress(ReadingProgress progress) async {
    final entries = await _readEntries();
    entries[_key(progress.kind, progress.id)] = progress.copyWith(
      updatedAt: progress.updatedAt ?? DateTime.now(),
    );
    // 超出上限时丢弃最旧的记录
    if (entries.length > _maxEntries) {
      final sorted = entries.entries.toList()
        ..sort((left, right) => _timeOf(right.value).compareTo(_timeOf(left.value)));
      entries
        ..clear()
        ..addEntries(sorted.take(_maxEntries));
    }
    await _writeEntries(entries);
  }

  /// [candidate] 是否比 [current] 更新；时间缺失时视为「不更新」，
  /// 避免用时间未知的服务端记录覆盖本地较新的位置。
  static bool _isNewer(ReadingProgress candidate, ReadingProgress current) {
    final candidateTime = candidate.updatedAt;
    if (candidateTime == null) {
      return false;
    }
    return candidateTime.isAfter(_timeOf(current));
  }

  @override
  Future<List<ReadingProgress>> readRecentProgress({int limit = 20}) async {
    final entries = await _readEntries();
    final values = entries.values.toList()
      ..sort((left, right) => _timeOf(right).compareTo(_timeOf(left)));
    return values.take(limit).toList(growable: false);
  }

  static DateTime _timeOf(ReadingProgress progress) =>
      progress.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  static String _key(ContentKind kind, String id) => '${kind.pathSegment}:$id';

  Future<Map<String, ReadingProgress>> _readEntries() async {
    final raw = await storage.readString(StorageKeys.readingProgress);
    if (raw == null || raw.isEmpty) {
      return <String, ReadingProgress>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, ReadingProgress>{};
      }
      final result = <String, ReadingProgress>{};
      decoded.forEach((key, value) {
        final map = value is Map
            ? value.map((k, v) => MapEntry('$k', v))
            : null;
        final progress = map == null ? null : ReadingProgress.fromJson(map);
        if (progress != null) {
          result['$key'] = progress;
        }
      });
      return result;
    } on Object catch (error) {
      AppLogger.warning(
        'ReadingRepositoryImpl',
        'failed to read reading progress',
        error,
      );
      return <String, ReadingProgress>{};
    }
  }

  Future<void> _writeEntries(Map<String, ReadingProgress> entries) async {
    final payload = <String, Object?>{
      for (final entry in entries.entries) entry.key: entry.value.toJson(),
    };
    await storage.writeString(StorageKeys.readingProgress, jsonEncode(payload));
  }

  Future<Map<String, Object?>?> _readJson(String key) async {
    final raw = await storage.readString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return decoded.map((k, v) => MapEntry('$k', v));
    } on Object catch (error) {
      AppLogger.warning(
        'ReadingRepositoryImpl',
        'failed to read settings for $key',
        error,
      );
      return null;
    }
  }
}
