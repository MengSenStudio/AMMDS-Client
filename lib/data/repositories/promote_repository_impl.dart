import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/logging/app_logger.dart';
import '../../core/storage/storage.dart';
import '../../domain/entities/promote.dart';
import '../../domain/repositories/repositories.dart';

/// 官方推送通告仓库实现。
///
/// 数据流与网页端 `app/src/utils/promote.ts` 对齐：
///
/// ```text
/// load()
///   ├─ 本地缓存未过期（10 分钟）→ 直接复用
///   ├─ 远端 JSON 拉取成功 → 校验 → 写缓存
///   └─ 拉取失败 → 回落本地缓存（过期也用）→ 都没有则为空列表
/// ```
///
/// 两个刻意的设计选择：
/// 1. **使用独立的 Dio 实例**，不挂载 AMMDS 的鉴权拦截器：
///    通告来自第三方域名，绝不能把访问令牌带过去；
/// 2. 「已读」按**当日**记录在本地（`yyyy-MM-dd`），与网页端语义一致——
///    只抑制当天的展示，次日若仍在窗口内会再次提醒。
final class PromoteRepositoryImpl implements PromoteRepository {
  /// 创建实现。
  PromoteRepositoryImpl({
    required this.storage,
    Dio? client,
    Uri? source,
    this.cacheTtl = const Duration(minutes: 10),
  }) : source = source ?? defaultSource,
       _client =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 6),
               receiveTimeout: const Duration(seconds: 6),
               responseType: ResponseType.plain,
             ),
           );

  /// 默认数据源：官方通告 JSON（与网页端同一地址）。
  ///
  /// 与网页端一样硬编码官方地址：通告属于「项目方推送给所有部署实例」的内容，
  /// 不由自建服务端提供。
  static final Uri defaultSource = Uri.parse(
    'https://file.lifebus.top/ammds/notice/promote.json',
  );

  /// 本地普通配置存储。
  final PreferencesStorage storage;

  /// 数据源地址（测试可注入）。
  final Uri source;

  /// 缓存有效期。
  final Duration cacheTtl;

  final Dio _client;

  /// 通告列表缓存键。
  static const String _cacheKey = 'promote_cache';

  /// 当日已读记录键（`{id: yyyy-MM-dd}`）。
  static const String _readKey = 'promote_read_dates';

  @override
  Future<List<AppPromote>> load() async {
    final cached = await _readCache();
    final now = DateTime.now();
    if (cached != null &&
        now.difference(cached.fetchedAt) < cacheTtl &&
        cached.items.isNotEmpty) {
      return cached.items;
    }
    try {
      final response = await _client.get<String>(source.toString());
      final items = _parse(response.data);
      if (items.isEmpty) {
        // 远端返回空数组时不要覆盖已有缓存（官方列表偶尔为空属于异常）
        return cached?.items ?? const <AppPromote>[];
      }
      await _writeCache(items, now);
      return items;
    } on Object catch (error) {
      AppLogger.warning('PromoteRepository', 'fetch promote failed', error);
      // 远端不可用时沿用旧缓存（过期也接受），保证离线仍能提醒
      return cached?.items ?? const <AppPromote>[];
    }
  }

  @override
  Future<List<AppPromote>> pending({DateTime? now}) async {
    final items = await load();
    final readDates = await _readDates();
    final today = _formatDate(now ?? DateTime.now());
    final current = now ?? DateTime.now();
    return items
        .where((item) => item.inWindow(current))
        .where((item) => readDates[item.id] != today)
        .toList(growable: false);
  }

  @override
  Future<void> markRead(String id, {DateTime? now}) async {
    if (id.isEmpty) {
      return;
    }
    try {
      final readDates = await _readDates();
      readDates[id] = _formatDate(now ?? DateTime.now());
      await storage.writeString(_readKey, jsonEncode(readDates));
    } on Object catch (error) {
      AppLogger.warning('PromoteRepository', 'mark promote read failed', error);
    }
  }

  Future<_PromoteCache?> _readCache() async {
    try {
      final raw = await storage.readString(_cacheKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final fetchedAt = decoded['fetched_at'];
      return _PromoteCache(
        items: _parse(decoded['items']),
        fetchedAt: fetchedAt is int
            ? DateTime.fromMillisecondsSinceEpoch(fetchedAt)
            : DateTime.fromMillisecondsSinceEpoch(0),
      );
    } on Object catch (error) {
      AppLogger.warning('PromoteRepository', 'read promote cache failed', error);
      return null;
    }
  }

  Future<void> _writeCache(List<AppPromote> items, DateTime fetchedAt) async {
    try {
      await storage.writeString(
        _cacheKey,
        jsonEncode(<String, Object?>{
          'fetched_at': fetchedAt.millisecondsSinceEpoch,
          'items': items
              .map(
                (item) => <String, Object?>{
                  'id': item.id,
                  'title': item.title,
                  'description': item.description,
                  'tip': item.tip,
                  'pushTime': _formatDateTime(item.pushTime),
                  'endTime': _formatDateTime(item.endTime),
                  'banner': item.banner?.toString(),
                  'website': item.website?.toString(),
                  'dialogTitle': item.dialogTitle,
                  'buttonText': item.buttonText,
                },
              )
              .toList(growable: false),
        }),
      );
    } on Object catch (error) {
      AppLogger.warning('PromoteRepository', 'write promote cache failed', error);
    }
  }

  Future<Map<String, String>> _readDates() async {
    try {
      final raw = await storage.readString(_readKey);
      if (raw == null || raw.isEmpty) {
        return <String, String>{};
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, String>{};
      }
      return decoded.map(
        (key, value) => MapEntry('$key', value is String ? value : ''),
      );
    } on Object catch (error) {
      AppLogger.warning('PromoteRepository', 'read promote states failed', error);
      return <String, String>{};
    }
  }

  /// 远端可能是「纯数组」或 `{ items: [...] }`；只保留 `id` 非空的合法条目。
  static List<AppPromote> _parse(Object? data) {
    Object? payload = data;
    if (data is String) {
      try {
        payload = jsonDecode(data);
      } on Object {
        return const <AppPromote>[];
      }
    }
    if (payload is Map) {
      payload = payload['items'] ?? payload['data'];
    }
    if (payload is! List) {
      return const <AppPromote>[];
    }
    return payload
        .map(AppPromote.fromJson)
        .whereType<AppPromote>()
        .toList(growable: false);
  }

  static String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  static String? _formatDateTime(DateTime? value) {
    if (value == null) {
      return null;
    }
    String two(int number) => number.toString().padLeft(2, '0');
    return '${_formatDate(value)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

/// 通告缓存。
final class _PromoteCache {
  const _PromoteCache({required this.items, required this.fetchedAt});

  final List<AppPromote> items;
  final DateTime fetchedAt;
}
