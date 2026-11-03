import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ugreen_cloud_shell/services/download_manager.dart';

void main() {
  test('下载管理器：从本地服务器下载文件并完成落盘', () async {
    const payload = 'hello-ugreen-download';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.set(
        'content-disposition',
        'attachment; filename="demo.bin"',
      );
      request.response.headers.set('content-length', '${payload.length}');
      request.response.add(payload.codeUnits);
      await request.response.close();
    });

    final workDir = await Directory.systemTemp.createTemp('ugreen_dl_test');
    final records = <Map<String, dynamic>>[];
    final manager = DownloadManager.forTesting(
      finalizeFile: (sourcePath, fileName, mimeType) async {
        final target = File('${workDir.path}${Platform.pathSeparator}$fileName');
        await File(sourcePath).copy(target.path);
        return target.path;
      },
      saveRecords: (list) async {
        records
          ..clear()
          ..addAll(list);
      },
      loadRecords: () async => null,
    );

    await manager.load();
    expect(manager.tasks, isEmpty);

    await manager.start(url: 'http://127.0.0.1:${server.port}/files/demo.bin');
    expect(manager.tasks, isNotEmpty);
    expect(manager.tasks.first.status, DownloadStatus.running);

    var task = manager.tasks.first;
    for (var i = 0; i < 200 && task.status == DownloadStatus.running; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      task = manager.tasks.first;
    }

    expect(task.status, DownloadStatus.done);
    expect(task.fileName, 'demo.bin');
    expect(task.receivedBytes, payload.length);
    expect(task.totalBytes, payload.length);
    expect(task.target, isNotEmpty);
    expect(await File(task.target).readAsString(), payload);
    expect(records, isNotEmpty);
    expect(records.first['fileName'], 'demo.bin');

    await server.close(force: true);
    await workDir.delete(recursive: true);
  });

  test('resolveFileName：优先使用 Content-Disposition 并清洗非法字符', () {
    expect(
      DownloadManager.resolveFileName(
        'http://nas/download/anything',
        r"attachment; filename*=UTF-8''%E7%94%B5%E5%BD%B1.mp4",
      ),
      '电影.mp4',
    );
    expect(
      DownloadManager.resolveFileName(
        'http://nas/download/anything',
        'attachment; filename="backup:01.zip"',
      ),
      'backup_01.zip',
    );
    expect(
      DownloadManager.resolveFileName(
        'http://nas/files/%E5%9B%BE%E7%89%87.png',
        '',
      ),
      '图片.png',
    );
    expect(
      DownloadManager.resolveFileName('http://nas/', ''),
      startsWith('download_'),
    );
  });
}
