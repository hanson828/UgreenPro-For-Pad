import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// 下载任务状态。
enum DownloadStatus { running, done, failed }

/// 一条下载记录。
@immutable
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.status,
    this.receivedBytes = 0,
    this.totalBytes = -1,
    this.target = '',
    this.createdAt = 0,
  });

  final String id;
  final String url;
  final String fileName;
  final String mimeType;
  final DownloadStatus status;

  /// 已接收字节数。
  final int receivedBytes;

  /// 总字节数，-1 表示未知。
  final int totalBytes;

  /// 下载完成后的目标：content:// URI 或文件路径。
  final String target;
  final int createdAt;

  double get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  DownloadTask copyWith({
    String? id,
    String? url,
    String? fileName,
    String? mimeType,
    DownloadStatus? status,
    int? receivedBytes,
    int? totalBytes,
    String? target,
    int? createdAt,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      status: status ?? this.status,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      target: target ?? this.target,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'url': url,
        'fileName': fileName,
        'mimeType': mimeType,
        'status': status.index,
        'receivedBytes': receivedBytes,
        'totalBytes': totalBytes,
        'target': target,
        'createdAt': createdAt,
      };

  static DownloadTask fromJson(Map<String, dynamic> json) {
    final statusIndex = (json['status'] as num?)?.toInt() ?? 0;
    return DownloadTask(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '未命名文件',
      mimeType: json['mimeType'] as String? ?? '',
      status: statusIndex >= 0 && statusIndex < DownloadStatus.values.length
          ? DownloadStatus.values[statusIndex]
          : DownloadStatus.failed,
      receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? -1,
      target: json['target'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 下载管理器：拦截网页下载，落盘到系统“下载”目录，并维护可持久化的记录列表。
class DownloadManager extends ChangeNotifier {
  DownloadManager._() {
    _finalizeFile = _finalizeViaPlatform;
    _saveRecords = _persistRecords;
    _loadRecords = _restoreRecords;
    _resolveTempDir = getTemporaryDirectory;
    unawaited(load());
  }

  /// 供单元测试注入落盘与持久化实现，避免依赖平台通道。
  @visibleForTesting
  DownloadManager.forTesting({
    required Future<String> Function(
      String sourcePath,
      String fileName,
      String mimeType,
    ) finalizeFile,
    required Future<void> Function(List<Map<String, dynamic>> records)
        saveRecords,
    Future<List<Map<String, dynamic>>?> Function()? loadRecords,
    Future<Directory> Function()? tempDirectory,
  }) {
    _finalizeFile = finalizeFile;
    _saveRecords = saveRecords;
    _loadRecords = loadRecords;
    _resolveTempDir =
        tempDirectory ?? (() async => Directory.systemTemp.createTempSync('ugreen_dl'));
  }

  static final DownloadManager instance = DownloadManager._();

  static const MethodChannel _filesChannel = MethodChannel(
    'ugreen_shell/files',
  );
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true, resetOnError: true),
  );
  static const String _storageKey = 'ugreen_shell_downloads_v1';
  static const int _maxRecords = 60;

  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36';

  late final Future<String> Function(String, String, String) _finalizeFile;
  late final Future<void> Function(List<Map<String, dynamic>>) _saveRecords;
  late final Future<List<Map<String, dynamic>>?> Function()? _loadRecords;
  late final Future<Directory> Function() _resolveTempDir;

  final List<DownloadTask> _tasks = <DownloadTask>[];
  int _lastNotifyAt = 0;
  bool _loaded = false;

  /// 当前任务列表（新任务在前）。
  List<DownloadTask> get tasks => List<DownloadTask>.unmodifiable(_tasks);

  /// 历史记录是否已加载完成。
  bool get isLoaded => _loaded;

  /// 从持久化恢复记录。
  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final loader = _loadRecords;
      final raw = loader == null ? null : await loader();
      final list = raw ??
          (jsonDecode(await _storage.read(key: _storageKey) ?? '[]') as List);
      _tasks
        ..clear()
        ..addAll(<DownloadTask>[
          for (final item in list)
            if (item is Map) DownloadTask.fromJson(Map<String, dynamic>.from(item)),
        ]);
    } catch (_) {
      // 记录损坏时忽略，保持空列表。
    }
    _loaded = true;
    notifyListeners();
  }

  /// 发起一次下载。立即返回，进度通过 listeners 通知。
  Future<void> start({
    required String url,
    String contentDisposition = '',
    String mimeType = '',
    int contentLength = -1,
  }) async {
    final id = 'dl_${DateTime.now().microsecondsSinceEpoch}';
    final fileName = resolveFileName(url, contentDisposition);
    _tasks.insert(
      0,
      DownloadTask(
        id: id,
        url: url,
        fileName: fileName,
        mimeType: mimeType.isEmpty ? guessMime(fileName) : mimeType,
        status: DownloadStatus.running,
        totalBytes: contentLength,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _trimRecords();
    notifyListeners();
    unawaited(_run(id));
  }

  /// 用系统应用打开已完成的文件，返回是否成功。
  Future<bool> open(DownloadTask task) async {
    if (task.status != DownloadStatus.done || task.target.isEmpty) {
      return false;
    }
    try {
      await _filesChannel
          .invokeMethod<void>('openFile', <String, dynamic>{'target': task.target});
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// 删除文件与记录。
  Future<void> remove(DownloadTask task) async {
    if (task.status == DownloadStatus.done && task.target.isNotEmpty) {
      try {
        await _filesChannel
            .invokeMethod<void>('deleteFile', <String, dynamic>{'target': task.target});
      } on PlatformException {
        // 文件可能已被系统清理，继续移除记录。
      }
    }
    _tasks.removeWhere((t) => t.id == task.id);
    notifyListeners();
    await _saveCurrent();
  }

  Future<void> _run(String id) async {
    HttpClient? client;
    try {
      final index = _tasks.indexWhere((t) => t.id == id);
      if (index < 0) {
        return;
      }
      final task = _tasks[index];
      final tempDir = await _resolveTempDir();
      final tempPath =
          '${tempDir.path}${Platform.pathSeparator}ugshell_$id.part';

      client = HttpClient();
      client.userAgent = _desktopUserAgent;
      final request = await client.getUrl(Uri.parse(task.url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final sink = File(tempPath).openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          _updateProgress(id, received);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      final total = response.contentLength > 0 ? response.contentLength : received;
      final target = await _finalizeFile(tempPath, task.fileName, task.mimeType);
      _patch(
        id,
        (t) => t.copyWith(
          status: DownloadStatus.done,
          receivedBytes: total,
          totalBytes: total,
          target: target,
        ),
      );
      await _saveCurrent();
    } catch (_) {
      _patch(id, (t) => t.copyWith(status: DownloadStatus.failed));
      await _saveCurrent();
    } finally {
      client?.close(force: true);
    }
  }

  void _updateProgress(String id, int received) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) {
      return;
    }
    _tasks[index] = _tasks[index].copyWith(receivedBytes: received);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNotifyAt > 120) {
      _lastNotifyAt = now;
      notifyListeners();
    }
  }

  void _patch(String id, DownloadTask Function(DownloadTask) updater) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) {
      return;
    }
    _tasks[index] = updater(_tasks[index]);
    notifyListeners();
  }

  void _trimRecords() {
    while (_tasks.length > _maxRecords) {
      _tasks.removeLast();
    }
  }

  Future<void> _saveCurrent() async {
    try {
      await _saveRecords(<Map<String, dynamic>>[
        for (final task in _tasks) task.toJson(),
      ]);
    } catch (_) {
      // 持久化失败不影响下载本身。
    }
  }

  Future<String> _finalizeViaPlatform(
    String sourcePath,
    String fileName,
    String mimeType,
  ) async {
    final target = await _filesChannel.invokeMethod<String>(
      'saveToDownloads',
      <String, dynamic>{
        'source': sourcePath,
        'fileName': fileName,
        'mimeType': mimeType,
      },
    );
    return target ?? '';
  }

  Future<void> _persistRecords(List<Map<String, dynamic>> records) async {
    await _storage.write(key: _storageKey, value: jsonEncode(records));
  }

  Future<List<Map<String, dynamic>>?> _restoreRecords() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return null;
    }
    return <Map<String, dynamic>>[
      for (final item in decoded)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  /// 从 Content-Disposition 或 URL 推断文件名。
  static String resolveFileName(String url, String contentDisposition) {
    var name = '';
    final cd = contentDisposition;
    final utf8Match =
        RegExp(r"filename\*\s*=\s*UTF-8''([^;]+)", caseSensitive: false)
            .firstMatch(cd);
    if (utf8Match != null) {
      name = Uri.decodeComponent(utf8Match.group(1)!);
    }
    if (name.isEmpty) {
      final quoted =
          RegExp(r'filename\s*=\s*"([^"]+)"', caseSensitive: false).firstMatch(cd);
      if (quoted != null) {
        name = quoted.group(1)!;
      }
    }
    if (name.isEmpty) {
      final plain =
          RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false).firstMatch(cd);
      if (plain != null) {
        name = plain.group(1)!.trim();
      }
    }
    if (name.isEmpty) {
      final path = Uri.tryParse(url)?.path ?? '';
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        try {
          name = Uri.decodeComponent(segments.last);
        } on FormatException {
          name = segments.last;
        }
      }
    }
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (name.isEmpty || name == '.') {
      name = 'download_${DateTime.now().millisecondsSinceEpoch}';
    }
    return name;
  }

  /// 依据扩展名猜测 MIME 类型。
  static String guessMime(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
        : '';
    const map = <String, String>{
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'mp4': 'video/mp4',
      'mkv': 'video/x-matroska',
      'mov': 'video/quicktime',
      'mp3': 'audio/mpeg',
      'flac': 'audio/flac',
      'wav': 'audio/wav',
      'pdf': 'application/pdf',
      'zip': 'application/zip',
      'rar': 'application/vnd.rar',
      '7z': 'application/x-7z-compressed',
      'txt': 'text/plain',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'apk': 'application/vnd.android.package-archive',
    };
    return map[ext] ?? 'application/octet-stream';
  }
}
