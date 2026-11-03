import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 应用锁凭据（数字密码 / 图形密码）的哈希工具：随机盐 + HMAC-SHA256 迭代，
/// 明文不落盘。8000 次迭代在平板上单次校验约几十毫秒，够拖慢暴力尝试，
/// 又不影响解锁手感。
const int kPinHashIterations = 8000;

/// 数字密码规则：4-6 位纯数字。
final RegExp _pinPattern = RegExp(r'^\d{4,6}$');

bool isValidPin(String pin) => _pinPattern.hasMatch(pin);

/// 图形密码最少连接的点数。
const int kPatternMinDots = 4;

/// 图形密码是否合法：3x3 九个点里至少连 4 个、且不重复。
bool isValidPattern(List<int> dots) {
  if (dots.length < kPatternMinDots) {
    return false;
  }
  if (dots.toSet().length != dots.length) {
    return false;
  }
  return dots.every((dot) => dot >= 0 && dot < 9);
}

/// 图形密码归一成可哈希的字符串，例如 "0-1-2-5"。
String encodePattern(List<int> dots) => dots.join('-');

String generatePinSalt([Random? random]) {
  final rnd = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  return base64UrlEncode(bytes);
}

String hashPin(String pin, String salt, {int iterations = kPinHashIterations}) {
  final key = utf8.encode(salt);
  List<int> digest = utf8.encode(pin);
  for (var i = 0; i < iterations; i++) {
    digest = Hmac(sha256, key).convert(digest).bytes;
  }
  return base64UrlEncode(digest);
}

/// 定时安全比较，避免按字符提前返回泄漏信息。
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
