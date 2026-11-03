import 'package:flutter/services.dart';

/// 系统文件选择器（Android SAF）桥接。
///
/// 网页里的 `<input type="file">` 被点击时，WebView 会回调
/// [AndroidWebViewController.setOnShowFileSelector]，这里负责弹出系统选择器并把
/// 选中的 content:// URI 交回去。用 ACTION_OPEN_DOCUMENT 是为了拿到可持久授权的
/// URI —— WebView 的渲染进程之后仍要读这些文件才能上传。
class FilePickerBridge {
  const FilePickerBridge._();

  static const MethodChannel _channel = MethodChannel('ugreen_shell/file_picker');

  /// 弹出系统文件选择器。用户取消时返回空列表。
  static Future<List<String>> pickFiles({
    bool multiple = false,
    List<String> mimeTypes = const <String>[],
  }) async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        'pickFiles',
        <String, Object?>{
          'multiple': multiple,
          'mimeTypes': mimeTypes,
        },
      );
      if (result == null) {
        return const <String>[];
      }
      return <String>[
        for (final item in result)
          if (item is String && item.isNotEmpty) item,
      ];
    } on PlatformException {
      return const <String>[];
    } on MissingPluginException {
      return const <String>[];
    }
  }

  /// 过滤网页给的 accept 列表：只保留真正的 MIME 类型，`*/*`、`.png` 之类丢掉。
  static List<String> normalizeMimeTypes(List<String> acceptTypes) {
    final out = <String>[];
    for (final raw in acceptTypes) {
      final type = raw.trim().toLowerCase();
      if (type.isEmpty || type == '*/*' || type.contains('*')) {
        continue;
      }
      if (!RegExp(r'^[a-z]+/[a-z0-9.+-]+$').hasMatch(type)) {
        continue;
      }
      if (!out.contains(type)) {
        out.add(type);
      }
    }
    return out;
  }
}
