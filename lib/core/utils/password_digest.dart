import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 登录密码摘要工具。
///
/// AMMDS 服务端的登录约定为：
///
/// ```text
/// 明文密码 --MD5--> 32 位小写十六进制 --再 MD5 x4--> loginPassword
/// ```
///
/// 即 `UserEntity.setPassword()` 先做一轮 MD5 写入 `password` 列，
/// `UserEntity.getLoginPassword()` 再以该摘要为输入连续做 4 轮 MD5，
/// 登录时服务端把请求中的密文 RSA 解密后与该值比对。
///
/// 因此客户端必须提交 **五轮 MD5 摘要在内的 RSA 密文**，
/// 而不是明文密码的密文。
abstract final class PasswordDigest {
  /// 服务端约定的摘要轮数。
  static const int rounds = 5;

  /// 计算登录用的五轮 MD5 摘要（32 位小写十六进制）。
  static String loginDigest(String plainPassword) {
    var current = plainPassword;
    for (var i = 0; i < rounds; i++) {
      current = md5.convert(utf8.encode(current)).toString();
    }
    return current;
  }

  /// 计算单轮 MD5（32 位小写十六进制）。
  static String md5Hex(String input) =>
      md5.convert(utf8.encode(input)).toString();
}
