import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ugreen_cloud_shell/services/pin_hash.dart';

void main() {
  group('PIN 规则', () {
    test('只接受 4-6 位数字', () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123456'), isTrue);
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('1234567'), isFalse);
      expect(isValidPin('12a4'), isFalse);
      expect(isValidPin(''), isFalse);
    });
  });

  group('PIN 哈希', () {
    test('同一 PIN + 同一盐 得到同一哈希', () {
      const salt = 'c2FsdHktc2FsdA==';
      expect(hashPin('1234', salt, iterations: 16),
          hashPin('1234', salt, iterations: 16));
    });

    test('不同盐或不同 PIN 得到不同哈希', () {
      const a = 'c2FsdHktc2FsdA==';
      const b = 'b3RoZXItc2FsdA==';
      final base = hashPin('1234', a, iterations: 16);
      expect(hashPin('1234', b, iterations: 16), isNot(base));
      expect(hashPin('4321', a, iterations: 16), isNot(base));
    });

    test('哈希不含明文 PIN', () {
      const salt = 'c2FsdHktc2FsdA==';
      expect(hashPin('2580', salt, iterations: 16), isNot(contains('2580')));
    });

    test('盐随机且长度足够', () {
      final random = Random(7);
      final salts = List.generate(8, (_) => generatePinSalt(random)).toSet();
      expect(salts.length, 8);
      for (final salt in salts) {
        expect(salt.length, greaterThanOrEqualTo(20));
      }
    });
  });

  group('图形密码', () {
    test('至少 4 个点且不重复', () {
      expect(isValidPattern([0, 1, 2, 5]), isTrue);
      expect(isValidPattern([0, 1, 2, 5, 8]), isTrue);
      expect(isValidPattern([0, 1, 2]), isFalse);
      expect(isValidPattern(<int>[]), isFalse);
      expect(isValidPattern([0, 1, 1, 2]), isFalse);
      expect(isValidPattern([0, 1, 2, 9]), isFalse);
    });

    test('点位串编码稳定', () {
      expect(encodePattern([0, 1, 2, 5]), '0-1-2-5');
      expect(encodePattern([8, 7, 6]), '8-7-6');
    });

    test('图形密码走同一套哈希且可校验', () {
      final salt = generatePinSalt();
      final hash = hashPin(encodePattern([0, 1, 2, 5]), salt);
      final ok = constantTimeEquals(
        hashPin(encodePattern([0, 1, 2, 5]), salt),
        hash,
      );
      final bad = constantTimeEquals(
        hashPin(encodePattern([0, 1, 2, 4]), salt),
        hash,
      );
      expect(ok, isTrue);
      expect(bad, isFalse);
    });
  });

  group('定时安全比较', () {
    test('相等与不等', () {
      expect(constantTimeEquals('abc', 'abc'), isTrue);
      expect(constantTimeEquals('abc', 'abd'), isFalse);
      expect(constantTimeEquals('abc', 'abcd'), isFalse);
      expect(constantTimeEquals('', ''), isTrue);
    });
  });
}
