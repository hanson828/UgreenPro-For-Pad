import 'package:flutter_test/flutter_test.dart';
import 'package:ugreen_cloud_shell/models/saved_account.dart';
import 'package:ugreen_cloud_shell/services/address_resolver.dart';

void main() {
  group('局域网地址', () {
    test('纯 IP 自动补全 HTTP 9999', () {
      final result = AddressResolver.resolve(ConnectionMode.lan, '192.168.31.70');
      expect(result.isValid, isTrue);
      expect(result.url, 'http://192.168.31.70:9999');
    });

    test('域名带 9443 端口时使用 HTTPS', () {
      final result = AddressResolver.resolve(ConnectionMode.lan, 'nas.local:9443');
      expect(result.isValid, isTrue);
      expect(result.url, 'https://nas.local:9443');
    });

    test('显式 http 地址补全 9999', () {
      final result = AddressResolver.resolve(
        ConnectionMode.lan,
        'http://192.168.31.70',
      );
      expect(result.url, 'http://192.168.31.70:9999');
    });

    test('显式 https 地址补全 9443', () {
      final result = AddressResolver.resolve(
        ConnectionMode.lan,
        'https://nas.example.com',
      );
      expect(result.url, 'https://nas.example.com:9443');
    });

    test('拒绝空地址', () {
      final result = AddressResolver.resolve(ConnectionMode.lan, '  ');
      expect(result.isValid, isFalse);
      expect(result.error, isNotEmpty);
    });
  });

  group('UGREENlink 地址', () {
    test('ID 生成 ug.link 地址', () {
      final result = AddressResolver.resolve(ConnectionMode.link, 'myNAS123');
      expect(result.isValid, isTrue);
      expect(result.url, 'https://ug.link/myNAS123');
      expect(result.display, 'ug.link/myNAS123');
    });

    test('完整地址会被规范化', () {
      final result = AddressResolver.resolve(
        ConnectionMode.link,
        'https://ug.link/myNAS123/',
      );
      expect(result.isValid, isTrue);
      expect(result.url, 'https://ug.link/myNAS123');
    });

    test('非法 ID 给出提示', () {
      final result = AddressResolver.resolve(ConnectionMode.link, 'my@NAS');
      expect(result.isValid, isFalse);
      expect(result.error, contains('UGREENlink ID'));
    });
  });
}
