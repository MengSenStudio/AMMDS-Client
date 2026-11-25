import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../errors/app_exception.dart';

/// RSA 公钥（仅包含 PKCS#1 v1.5 加密所需参数）。
///
/// AMMDS 服务端的 `/api/oauth/secret` 下发 PEM 编码的 SubjectPublicKeyInfo
/// 公钥，前端用其加密登录密码后再调用登录接口。客户端复用同一套约定，
/// 使登录请求与服务端实现保持兼容，同时避免在网络上传输明文密码。
final class RsaPublicKey {
  /// 创建公钥。
  const RsaPublicKey({required this.modulus, required this.exponent});

  /// 模数 n。
  final BigInt modulus;

  /// 公开指数 e。
  final BigInt exponent;

  /// 密钥字节长度。
  int get byteLength => (modulus.bitLength + 7) >> 3;

  /// 解析 PEM（`-----BEGIN PUBLIC KEY-----`）或裸 Base64 DER。
  ///
  /// 支持 `SubjectPublicKeyInfo`（`PUBLIC KEY`）与 `RSAPublicKey`
  /// （`RSA PUBLIC KEY`）两种结构。
  static RsaPublicKey parse(String pem) {
    final base64Body = pem
        .replaceAll(RegExp('-----BEGIN [^-]+-----'), '')
        .replaceAll(RegExp('-----END [^-]+-----'), '')
        .replaceAll(RegExp(r'\s'), '');
    if (base64Body.isEmpty) {
      throw const ParseError('RSA public key is empty');
    }
    final Uint8List der;
    try {
      der = base64.decode(base64Body);
    } on FormatException catch (error) {
      throw ParseError('RSA public key is not valid Base64', cause: error);
    }
    try {
      return _parseDer(der);
    } on AppException {
      rethrow;
    } catch (error) {
      throw ParseError('Failed to parse RSA public key', cause: error);
    }
  }

  /// PKCS#1 v1.5 加密，返回密文字节。
  Uint8List encryptPkcs1(Uint8List plain) {
    final keyLength = byteLength;
    // EM = 0x00 || 0x02 || PS || 0x00 || M，PS 至少 8 字节非零随机数。
    if (plain.length > keyLength - 11) {
      throw const ValidationError('Plaintext too long for RSA key size');
    }
    final random = Random.secure();
    final paddingLength = keyLength - plain.length - 3;
    final encoded = Uint8List(keyLength);
    encoded[0] = 0x00;
    encoded[1] = 0x02;
    for (var index = 2; index < 2 + paddingLength; index++) {
      encoded[index] = random.nextInt(255) + 1; // 1..255，避开 0x00
    }
    encoded[2 + paddingLength] = 0x00;
    encoded.setRange(3 + paddingLength, keyLength, plain);

    final message = _bytesToBigInt(encoded);
    final cipher = message.modPow(exponent, modulus);
    return _bigIntToBytes(cipher, keyLength);
  }

  /// 加密 UTF-8 文本并返回 Base64 字符串。
  String encryptUtf8ToBase64(String text) =>
      base64.encode(encryptPkcs1(Uint8List.fromList(utf8.encode(text))));

  static RsaPublicKey _parseDer(Uint8List der) {
    // 兼容三种常见编码：
    // 1. SubjectPublicKeyInfo: SEQUENCE { AlgorithmIdentifier, BIT STRING }
    // 2. RSAPublicKey:         SEQUENCE { INTEGER n, INTEGER e }
    // 3. 上述结构外再包一层 SEQUENCE
    //
    // 直接按 TLV 递归遍历整个 DER 树，收集其中的 INTEGER。
    // RSA 公钥中只有模数与指数两个 INTEGER，因此取前两个即可，
    // 该实现与嵌套层数、是否带算法标识无关。
    final values = <BigInt>[];
    _collectIntegers(der, values);
    if (values.length < 2) {
      throw const ParseError('RSA public key is missing integers');
    }
    final modulus = values[0];
    final exponent = values[1];
    if (modulus <= BigInt.zero || exponent <= BigInt.zero) {
      throw const ParseError('RSA public key has invalid integers');
    }
    return RsaPublicKey(modulus: modulus, exponent: exponent);
  }

  /// 递归遍历 DER TLV，按出现顺序收集所有 INTEGER。
  static void _collectIntegers(Uint8List bytes, List<BigInt> output) {
    var index = 0;
    while (index < bytes.length) {
      final tag = bytes[index];
      var cursor = index + 1;
      if (cursor >= bytes.length) {
        throw const ParseError('DER element is truncated');
      }
      var length = bytes[cursor++];
      if (length & 0x80 != 0) {
        final byteCount = length & 0x7f;
        if (byteCount == 0 ||
            byteCount > 4 ||
            cursor + byteCount > bytes.length) {
          throw const ParseError('Unsupported DER length encoding');
        }
        length = 0;
        for (var i = 0; i < byteCount; i++) {
          length = (length << 8) | bytes[cursor++];
        }
      }
      if (cursor + length > bytes.length) {
        throw const ParseError('DER value length is out of range');
      }
      final value = Uint8List.sublistView(bytes, cursor, cursor + length);
      // 0x02 INTEGER、0x30 SEQUENCE、0x03 BIT STRING（跳过未使用比特数字节）
      if (tag == 0x02) {
        output.add(_bytesToBigInt(value));
      } else if (tag == 0x30) {
        _collectIntegers(value, output);
      } else if (tag == 0x03 && value.isNotEmpty) {
        _collectIntegers(Uint8List.sublistView(value, 1), output);
      }
      index = cursor + length;
    }
  }
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _bigIntToBytes(BigInt value, int length) {
  final result = Uint8List(length);
  var current = value;
  for (var i = length - 1; i >= 0; i--) {
    result[i] = (current & BigInt.from(0xff)).toInt();
    current = current >> 8;
  }
  return result;
}
