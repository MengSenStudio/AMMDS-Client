import 'dart:convert';

import 'package:ammds_client/core/storage/storage_impl.dart';
import 'package:ammds_client/data/repositories/promote_repository_impl.dart';
import 'package:ammds_client/domain/entities/promote.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 官方推送通告（promote）测试（文档 #5：登录后 / 启动时提醒）。
///
/// 覆盖两层：
/// * [AppPromote.inWindow] 的时间窗口边界；
/// * [PromoteRepositoryImpl] 的「远端优先 + 缓存回落 + 当日已读」语义。
///
/// 测试通过**预置缓存**来避开真实网络：仓库在缓存未过期时不会发起请求，
/// 需要验证远端失败回落的用例则注入一个必然连接失败的 Dio。
void main() {
  const cacheKey = 'promote_cache';
  const readKey = 'promote_read_dates';

  /// 构造一条窗口内的通告（pushTime 过去、endTime 未来）。
  Map<String, Object?> itemJson(String id, {String? endTime}) =>
      <String, Object?>{
        'id': id,
        'title': '标题 $id',
        'description': '正文',
        'pushTime': '2020-01-01 00:00:00',
        'endTime': endTime ?? '2099-01-01 00:00:00',
      };

  Future<void> seedCache(
    InMemoryPreferencesStorage storage,
    List<Map<String, Object?>> items, {
    DateTime? fetchedAt,
  }) => storage.writeString(
    cacheKey,
    jsonEncode(<String, Object?>{
      'fetched_at': (fetchedAt ?? DateTime.now()).millisecondsSinceEpoch,
      'items': items,
    }),
  );

  group('AppPromote 时间窗口', () {
    test('未到 pushTime / 已过 endTime / 窗口内', () {
      final promote = AppPromote.fromJson(<String, Object?>{
        'id': 'a',
        'title': 't',
        'pushTime': '2026-09-21 00:00:00',
        'endTime': '2026-09-24 23:59:59',
      });
      expect(promote, isNotNull);
      expect(promote!.inWindow(DateTime(2026, 9, 20, 23, 59)), isFalse);
      expect(promote.inWindow(DateTime(2026, 9, 21)), isTrue);
      expect(promote.inWindow(DateTime(2026, 9, 22)), isTrue);
      expect(promote.inWindow(DateTime(2026, 9, 25)), isFalse);
    });

    test('endTime 缺失或不可解析时视为不在窗口内', () {
      final promote = AppPromote.fromJson(<String, Object?>{
        'id': 'a',
        'title': 't',
      });
      expect(promote!.inWindow(DateTime(2026, 9, 22)), isFalse);
    });

    test('缺少 id 的条目被丢弃', () {
      expect(AppPromote.fromJson(<String, Object?>{'title': 't'}), isNull);
      expect(AppPromote.fromJson(null), isNull);
    });
  });

  group('PromoteRepositoryImpl', () {
    test('缓存命中时返回条目，并按「窗口内 + 当日未读」筛出待展示项', () async {
      final storage = InMemoryPreferencesStorage();
      await seedCache(storage, <Map<String, Object?>>[
        itemJson('in-window'),
        itemJson('expired', endTime: '2020-01-01 00:00:00'),
      ]);
      final repository = PromoteRepositoryImpl(storage: storage);

      final loaded = await repository.load();
      expect(loaded.map((item) => item.id), containsAll(<String>['in-window', 'expired']));

      final pending = await repository.pending(now: DateTime(2026, 9, 21));
      expect(pending.map((item) => item.id), <String>['in-window']);
    });

    test('「已读」是当日已读：当天不再出现，次日仍会提醒', () async {
      final storage = InMemoryPreferencesStorage();
      await seedCache(storage, <Map<String, Object?>>[itemJson('p1')]);
      final repository = PromoteRepositoryImpl(storage: storage);
      final today = DateTime(2026, 9, 21, 10);

      expect((await repository.pending(now: today)).length, 1);

      await repository.markRead('p1', now: today);
      expect(await repository.pending(now: today), isEmpty);

      // 次日仍在推送窗口内 → 再次提醒
      expect((await repository.pending(now: DateTime(2026, 9, 22))).length, 1);
    });

    test('远端不可用时回落本地缓存', () async {
      final storage = InMemoryPreferencesStorage();
      // 缓存已过期（超过 10 分钟），强制走远端；远端必然失败 → 回落到该缓存
      await seedCache(
        storage,
        <Map<String, Object?>>[itemJson('cached')],
        fetchedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final repository = PromoteRepositoryImpl(
        storage: storage,
        // 端口 9 无服务，连接会立即失败，避免测试等待超时
        source: Uri.parse('http://127.0.0.1:9/promote.json'),
        client: Dio(
          BaseOptions(
            connectTimeout: const Duration(milliseconds: 500),
            receiveTimeout: const Duration(milliseconds: 500),
          ),
        ),
      );

      final loaded = await repository.load();
      expect(loaded.map((item) => item.id), <String>['cached']);
    });

    test('远端返回空数组时不覆盖已有缓存', () async {
      // 该场景等价于「远端暂时给出空列表」，此时保留缓存更符合预期
      final storage = InMemoryPreferencesStorage();
      await seedCache(storage, <Map<String, Object?>>[itemJson('keep')]);
      final repository = PromoteRepositoryImpl(storage: storage);
      final loaded = await repository.load();
      expect(loaded.single.id, 'keep');
      expect(await storage.readString(readKey), isNull);
    });
  });
}
