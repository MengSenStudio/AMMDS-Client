import 'dart:io';

import 'package:ammds_client/core/storage/storage.dart';
import 'package:ammds_client/core/storage/storage_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryPreferencesStorage', () {
    test('读写字符串与列表', () async {
      final storage = InMemoryPreferencesStorage();
      await storage.writeString('k', 'v');
      expect(await storage.readString('k'), 'v');
      await storage.writeStringList('list', <String>['a', 'b']);
      expect(await storage.readStringList('list'), <String>['a', 'b']);
      await storage.remove('k');
      expect(await storage.readString('k'), isNull);
      await storage.clear();
      expect(await storage.readStringList('list'), isEmpty);
    });
  });

  group('InMemorySecureStorage', () {
    test('写入 / 读取 / 删除 / 清空', () async {
      final storage = InMemorySecureStorage();
      await storage.write(StorageKeys.accessToken, 'token-a');
      expect(await storage.read(StorageKeys.accessToken), 'token-a');
      await storage.delete(StorageKeys.accessToken);
      expect(await storage.read(StorageKeys.accessToken), isNull);
      await storage.write(StorageKeys.refreshToken, 'r');
      await storage.clear();
      expect(await storage.read(StorageKeys.refreshToken), isNull);
    });
  });

  group('FilePreferencesStorage', () {
    late Directory directory;
    late File file;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ammds_prefs');
      file = File('${directory.path}${Platform.pathSeparator}prefs.json');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test('写入后落盘并可被新实例读取', () async {
      final first = FilePreferencesStorage(file: file);
      await first.writeString(StorageKeys.themeMode, 'dark');
      await first.writeStringList(StorageKeys.serverProfiles, <String>['a']);

      final second = FilePreferencesStorage(file: file);
      expect(await second.readString(StorageKeys.themeMode), 'dark');
      expect(await second.readStringList(StorageKeys.serverProfiles), <String>[
        'a',
      ]);
    });

    test('文件损坏时降级为空配置而不是抛异常', () async {
      await file.writeAsString('{not json');
      final storage = FilePreferencesStorage(file: file);
      expect(await storage.readString('any'), isNull);
      await storage.writeString('any', 'value');
      expect(await storage.readString('any'), 'value');
    });

    test('clear 清空全部键', () async {
      final storage = FilePreferencesStorage(file: file);
      await storage.writeString('a', '1');
      await storage.writeString('b', '2');
      await storage.clear();
      expect(await storage.readString('a'), isNull);
      expect(await storage.readString('b'), isNull);
    });
  });

  group('FileSecureStorage', () {
    late Directory directory;
    late File file;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ammds_secure');
      file = File('${directory.path}${Platform.pathSeparator}secure.bin');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test('令牌不以明文落盘', () async {
      final storage = FileSecureStorage(
        file: file,
        obfuscationSecret: 'test-secret',
      );
      await storage.write(StorageKeys.accessToken, 'super-secret-token');
      final raw = await file.readAsString();
      expect(raw.contains('super-secret-token'), isFalse);
    });

    test('相同密钥可以往返读取', () async {
      final first = FileSecureStorage(
        file: file,
        obfuscationSecret: 'test-secret',
      );
      await first.write(StorageKeys.accessToken, 'token-1');
      await first.write(StorageKeys.refreshToken, 'refresh-1');

      final second = FileSecureStorage(
        file: file,
        obfuscationSecret: 'test-secret',
      );
      expect(await second.read(StorageKeys.accessToken), 'token-1');
      expect(await second.read(StorageKeys.refreshToken), 'refresh-1');
    });

    test('删除与清空', () async {
      final storage = FileSecureStorage(
        file: file,
        obfuscationSecret: 'test-secret',
      );
      await storage.write('a', '1');
      await storage.write('b', '2');
      await storage.delete('a');
      expect(await storage.read('a'), isNull);
      expect(await storage.read('b'), '2');
      await storage.clear();
      expect(await storage.read('b'), isNull);
    });
  });
}
