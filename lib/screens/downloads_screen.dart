import 'package:flutter/material.dart';

import '../services/download_manager.dart';
import '../theme/app_theme.dart';

/// 下载管理：查看进度、打开或删除已下载的文件。
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final DownloadManager _manager = DownloadManager.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvasTop,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '下载管理',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '返回',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 20, endIndent: 20),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _manager,
                    builder: (context, _) {
                      final tasks = _manager.tasks;
                      if (tasks.isEmpty) {
                        return _buildEmpty();
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _buildTile(context, tasks[index]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.download_done_rounded,
              size: 30,
              color: AppColors.brandDark,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '暂无下载记录',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            '在网页中下载的文件会保存到平板“下载/Ugreen_Pro_For_Pad”目录',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(BuildContext context, DownloadTask task) {
    final subtitle = switch (task.status) {
      DownloadStatus.running => task.totalBytes > 0
          ? '${formatBytes(task.receivedBytes)} / ${formatBytes(task.totalBytes)}'
          : formatBytes(task.receivedBytes),
      DownloadStatus.done => formatBytes(task.receivedBytes),
      DownloadStatus.failed => '下载失败',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          _fileIcon(task.mimeType, task.fileName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: task.status == DownloadStatus.failed
                            ? AppColors.danger
                            : AppColors.muted,
                      ),
                    ),
                    if (task.status == DownloadStatus.running &&
                        task.totalBytes > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${(task.progress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandDark,
                        ),
                      ),
                    ],
                  ],
                ),
                if (task.status == DownloadStatus.running) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: task.totalBytes > 0 ? task.progress : null,
                      minHeight: 3.5,
                      backgroundColor: AppColors.line,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (task.status == DownloadStatus.done)
            IconButton(
              tooltip: '打开',
              onPressed: () => _open(task),
              icon: const Icon(Icons.open_in_new_rounded, size: 19),
            ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _confirmRemove(task),
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _fileIcon(String mimeType, String fileName) {
    final type = mimeType.isEmpty ? DownloadManager.guessMime(fileName) : mimeType;
    final icon = switch (type) {
      String t when t.startsWith('image/') => Icons.image_rounded,
      String t when t.startsWith('video/') => Icons.movie_rounded,
      String t when t.startsWith('audio/') => Icons.music_note_rounded,
      'application/pdf' => Icons.picture_as_pdf_rounded,
      String t when t.contains('zip') || t.contains('rar') || t.contains('7z') =>
        Icons.folder_zip_rounded,
      'application/vnd.android.package-archive' => Icons.android_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 21, color: AppColors.brandDark),
    );
  }

  Future<void> _open(DownloadTask task) async {
    final opened = await _manager.open(task);
    if (!mounted) {
      return;
    }
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到可打开此文件的应用')),
      );
    }
  }

  Future<void> _confirmRemove(DownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('将从“下载”目录删除 ${task.fileName}，确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _manager.remove(task);
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 0) {
      return '未知大小';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}
