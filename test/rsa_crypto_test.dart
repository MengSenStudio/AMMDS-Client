import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ammds_client/core/errors/app_exception.dart';
import 'package:ammds_client/core/utils/rsa_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/mock_ammds_server.dart';

void main() {
  group('RsaPublicKey', () {
    test('解析 PEM 公钥并加密，服务端可解密还原', () async {
      final server = MockAmmdsServer();
      await server.start();
      addTearDown(server.stop);

      final pem = await _publicKeyPem(server);
      final key = RsaPublicKey.parse(pem);
      expect(key.byteLength, greaterThan(0));

      final encrypted = key.encryptUtf8ToBase64('ammds-secret');
      expect(encrypted, isNotEmpty);

      // 通过测试桩的登录端点验证：服务端能解出原始密码。
      final result = await _login(server, encrypted);
      expect(result, isTrue);
    });

    test('支持裸露的 Base64 DER（无 PEM 头）', () async {
      final server = MockAmmdsServer();
      await server.start();
      addTearDown(server.stop);
      final pem = await _publicKeyPem(server);
      final body = pem
          .replaceAll(RegExp('-----BEGIN [^-]+-----'), '')
          .replaceAll(RegExp('-----END [^-]+-----'), '')
          .replaceAll(RegExp(r'\s'), '');

      final key = RsaPublicKey.parse(body);
      final encrypted = key.encryptUtf8ToBase64('hello');
      expect(encrypted, isNotEmpty);
    });

    test('空公钥抛出 ParseError', () {
      expect(() => RsaPublicKey.parse('   '), throwsA(isA<ParseError>()));
    });

    test('非法 Base64 抛出 ParseError', () {
      expect(
        () => RsaPublicKey.parse(
          '-----BEGIN PUBLIC KEY-----\n!!!\n-----END PUBLIC KEY-----',
        ),
        throwsA(isA<ParseError>()),
      );
    });

    test('明文过长时抛出 ValidationError', () async {
      final server = MockAmmdsServer();
      await server.start();
      addTearDown(server.stop);
      final key = RsaPublicKey.parse(await _publicKeyPem(server));
      final tooLong = 'x' * (key.byteLength - 10);
      expect(
        () => key.encryptUtf8ToBase64(tooLong),
        throwsA(isA<ValidationError>()),
      );
    });

    test('同一明文两次加密产生不同密文（随机填充）', () async {
      final server = MockAmmdsServer();
      await server.start();
      addTearDown(server.stop);
      final key = RsaPublicKey.parse(await _publicKeyPem(server));
      final first = key.encryptUtf8ToBase64('same-input');
      final second = key.encryptUtf8ToBase64('same-input');
      expect(first, isNot(equals(second)));
    });

    test('加密结果与服务端公钥位数一致', () async {
      final server = MockAmmdsServer();
      await server.start();
      addTearDown(server.stop);
      final key = RsaPublicKey.parse(await _publicKeyPem(server));
      final cipher = key.encryptPkcs1(Uint8List.fromList(utf8.encode('p')));
      expect(cipher.length, key.byteLength);
      expect(key.byteLength, greaterThanOrEqualTo(64));
    });

    test('服务端私钥可解出客户端加密的密码', () async {
      final server = MockAmmdsServer();
      await server.start();
      addTearDown(server.stop);
      final key = RsaPublicKey.parse(server.publicKeyPem);
      final cipher = key.encryptUtf8ToBase64('ammds-secret');
      expect(server.decryptPassword(cipher), 'ammds-secret');
    });
  });
}

Future<String> _publicKeyPem(MockAmmdsServer server) async {
  final client = _SimpleClient(server.baseUrl);
  final response = await client.get('/api/oauth/secret');
  final map = response as Map<String, Object?>;
  final data = map['data'] as Map<String, Object?>;
  return data['publicKey']! as String;
}

Future<bool> _login(MockAmmdsServer server, String encryptedPassword) async {
  final client = _SimpleClient(server.baseUrl);
  final response = await client.post(
    '/api/client/v1/auth/login',
    <String, Object?>{
      'username': server.username,
      'password': encryptedPassword,
    },
  );
  return response is Map && response['code'] == 0;
}

/// 极简 HTTP 客户端（避免在工具类测试中引入 Dio）。
final class _SimpleClient {
  _SimpleClient(this.baseUrl);

  final String baseUrl;

  HttpClient _create() => HttpClient();

  Future<Object?> get(String path) async {
    final client = _create();
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl$path'));
      final response = await request.close();
      return await _decode(response);
    } finally {
      client.close();
    }
  }

  Future<Object?> post(String path, Map<String, Object?> body) async {
    final client = _create();
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      return await _decode(response);
    } finally {
      client.close();
    }
  }

  Future<Object?> _decode(Stream<List<int>> response) async {
    final text = await utf8.decoder.bind(response).join();
    return jsonDecode(text);
  }
}
