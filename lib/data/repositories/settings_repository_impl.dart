import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../core/storage/storage.dart';
import '../../domain/entities/server.dart';
import '../../domain/repositories/repositories.dart';

/// 设置仓库实现（文档 #42 / #43）。
///
/// 普通配置（服务器列表、主题、语言）走 [PreferencesStorage]，
/// 不在其中保存任何令牌或密码。
final class SettingsRepositoryImpl implements SettingsRepository {
  /// 创建实现。
  SettingsRepositoryImpl({required this.storage});

  /// 普通配置存储。
  final PreferencesStorage storage;

  @override
  Future<String?> readThemeMode() => storage.readString(StorageKeys.themeMode);

  @override
  Future<void> writeThemeMode(String value) =>
      storage.writeString(StorageKeys.themeMode, value);

  @override
  Future<String?> readLocale() => storage.readString(StorageKeys.locale);

  @override
  Future<void> writeLocale(String value) =>
      storage.writeString(StorageKeys.locale, value);

  @override
  Future<List<ServerProfile>> readServerProfiles() async {
    final raw = await storage.readString(StorageKeys.serverProfiles);
    if (raw == null || raw.isEmpty) {
      return const <ServerProfile>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <ServerProfile>[];
      }
      final profiles = <ServerProfile>[];
      for (final item in decoded) {
        if (item is Map) {
          profiles.add(
            ServerProfile.fromJson(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          );
        }
      }
      return profiles;
    } on Object catch (error) {
      AppLogger.warning(
        'SettingsRepositoryImpl',
        'failed to read server profiles',
        error,
      );
      return const <ServerProfile>[];
    }
  }

  @override
  Future<void> saveServerProfiles(List<ServerProfile> profiles) =>
      storage.writeString(
        StorageKeys.serverProfiles,
        jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
      );

  @override
  Future<String?> readActiveServerId() =>
      storage.readString(StorageKeys.activeServerId);

  @override
  Future<void> writeActiveServerId(String? serverId) async {
    if (serverId == null) {
      await storage.remove(StorageKeys.activeServerId);
      return;
    }
    await storage.writeString(StorageKeys.activeServerId, serverId);
  }
}
