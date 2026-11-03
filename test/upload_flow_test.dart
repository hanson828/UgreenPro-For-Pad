import 'package:flutter_test/flutter_test.dart';
import 'package:ugreen_cloud_shell/services/file_picker_bridge.dart';
import 'package:ugreen_cloud_shell/services/upload_script.dart';

void main() {
  group('FilePickerBridge.normalizeMimeTypes', () {
    test('丢掉通配符、扩展名和空值，只留真正的 MIME', () {
      expect(
        FilePickerBridge.normalizeMimeTypes(const [
          '*/*',
          '',
          '.png',
          'image/png',
          'image/png',
          ' video/mp4 ',
        ]),
        <String>['image/png', 'video/mp4'],
      );
    });

    test('网页没给 accept 时返回空列表（等于不限制类型）', () {
      expect(FilePickerBridge.normalizeMimeTypes(const <String>[]), isEmpty);
    });

    test('大小写不敏感', () {
      expect(
        FilePickerBridge.normalizeMimeTypes(const ['Application/PDF']),
        <String>['application/pdf'],
      );
    });
  });

  group('buildUploadScript', () {
    test('走的是网页右键菜单同一条路径', () {
      final script = buildUploadScript();
      expect(script, contains("'contextmenu'"));
      expect(script, contains('上传到'));
      expect(script, contains('上传文件'));
    });

    test('结果通过UGShellBridge 回传，并带防重入标记', () {
      final script = buildUploadScript();
      expect(script, contains('UGShellBridge.postMessage'));
      expect(script, contains("type: 'upload'"));
      expect(script, contains('__ugUploading'));
    });

    test('脚本自带错误码，供 Dart 侧给出对应提示', () {
      final script = buildUploadScript();
      for (final code in <String>['no_list', 'no_menu', 'no_submenu']) {
        expect(script, contains(code));
      }
    });
  });
}
