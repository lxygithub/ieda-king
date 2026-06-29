import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/shared_file.dart';

class FileHandler {
  static const _uuid = Uuid();

  /// Detect type from MIME string or fallback to extension
  static SharedFileType detectType(String? mimeType, String name) {
    final mime = mimeType ?? lookupMimeType(name) ?? '';
    if (mime.startsWith('image/')) return SharedFileType.image;
    if (mime.startsWith('video/')) return SharedFileType.video;
    if (mime.startsWith('audio/')) return SharedFileType.audio;
    if (mime == 'text/plain' || mime == 'text/html') return SharedFileType.text;
    if (mime == 'application/vnd.android.package-archive') {
      return SharedFileType.apk;
    }
    if (mime.startsWith('application/') || mime == 'text/csv') {
      return SharedFileType.document;
    }
    final ext = name.toLowerCase().split('.').lastOrNull;
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic']
        .contains(ext)) {
      return SharedFileType.image;
    }
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) {
      return SharedFileType.video;
    }
    if (['mp3', 'wav', 'aac', 'flac', 'ogg'].contains(ext)) {
      return SharedFileType.audio;
    }
    if (['txt', 'md', 'html', 'xml', 'json', 'csv'].contains(ext)) {
      return SharedFileType.text;
    }
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx']
        .contains(ext)) {
      return SharedFileType.document;
    }
    if (ext == 'apk' || ext == 'apkm') {
      return SharedFileType.apk;
    }
    return SharedFileType.other;
  }

  /// Copy shared file into app's persistent storage
  static Future<SharedFile> handleSharedFile({
    String? sharedPath,
    String? textContent,
    String? mimeType,
  }) async {
    if (sharedPath == null && textContent == null) {
      throw ArgumentError('Either sharedPath or textContent must be provided');
    }
    final id = _uuid.v7();
    final now = DateTime.now();
    final dir = await getAppDocumentDir();
    final targetDir = Directory('${dir.path}/received');

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    if (textContent != null) {
      final name = 'text_${now.millisecondsSinceEpoch}.txt';
      final target = File('${targetDir.path}/$name');
      await target.writeAsString(textContent, flush: true);
      return SharedFile(
        id: id,
        name: name,
        type: SharedFileType.text,
        localPath: target.path,
        textContent: textContent,
        receivedAt: now,
        mimeType: 'text/plain',
        fileSize: textContent.length,
      );
    }

    final source = File(sharedPath!);
    if (!await source.exists()) {
      throw Exception('Source file not found: $sharedPath');
    }

    final stat = await source.stat();
    final originalName = source.uri.pathSegments.lastOrNull ?? 'file';
    final ext = originalName.contains('.')
        ? '.${originalName.split('.').last}'
        : '';
    // avoid name collision
    final safeName = '${now.millisecondsSinceEpoch}_$id$ext';
    final target = File('${targetDir.path}/$safeName');

    await source.copy(target.path);
    final type = detectType(mimeType, originalName);

    return SharedFile(
      id: id,
      name: originalName,
      type: type,
      localPath: target.path,
      sourceUri: sharedPath,
      receivedAt: now,
      mimeType: mimeType ?? lookupMimeType(originalName),
      fileSize: stat.size,
    );
  }

  /// Handle multiple shared files (ACTION_SEND_MULTIPLE)
  static Future<List<SharedFile>> handleMultipleFiles(
    List<String> paths, {
    String? mimeType,
  }) async {
    final results = <SharedFile>[];
    for (final p in paths) {
      try {
        final f = await handleSharedFile(sharedPath: p, mimeType: mimeType);
        results.add(f);
      } catch (_) {
        // skip individual failures
      }
    }
    return results;
  }

  static Future<Directory> getAppDocumentDir() =>
      getApplicationDocumentsDirectory();

  /// Total size of received/ directory in bytes
  static Future<int> getCacheSize() async {
    final dir = Directory('${(await getAppDocumentDir()).path}/received');
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final f in dir.list(recursive: true)) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  /// Delete all files in received/ directory. Returns number of files deleted.
  static Future<int> clearCache() async {
    final dir = Directory('${(await getAppDocumentDir()).path}/received');
    if (!await dir.exists()) return 0;
    int count = 0;
    await for (final f in dir.list()) {
      try {
        await f.delete();
        count++;
      } catch (_) {}
    }
    return count;
  }

  /// Format bytes to human-readable string
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Try to open a file with system handler
  static Future<bool> openFile(SharedFile file) async {
    if (file.localPath == null) return false;
    // open_filex handles this
    return true;
  }

  /// Extract text preview from file (for documents / text files)
  static Future<String?> readTextPreview(SharedFile file) async {
    if (file.textContent != null) return file.textContent;
    if (file.localPath == null) return null;
    if (file.type != SharedFileType.text &&
        file.type != SharedFileType.document) {
      return null;
    }
    try {
      final f = File(file.localPath!);
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      // Only show first 2k as preview
      return utf8.decode(bytes.take(2048).toList(), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }
}
