import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shared_file.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../services/s3_service.dart';
import '../utils/file_handler.dart';

class TimelineProvider extends ChangeNotifier {
  List<SharedFile> _files = [];
  bool _initialized = false;
  bool _loading = false;
  String _searchQuery = '';
  Set<SharedFileType> _typeFilter = {};

  List<SharedFile> get files => List.unmodifiable(_files);
  bool get initialized => _initialized;
  bool get loading => _loading;
  String get searchQuery => _searchQuery;
  Set<SharedFileType> get typeFilter => _typeFilter;

  bool get isSearching => _searchQuery.isNotEmpty;
  bool get hasTypeFilter => _typeFilter.isNotEmpty;

  /// Combined filter: search + type
  List<SharedFile> get filteredFiles {
    var result = _files;
    if (_searchQuery.isNotEmpty) {
      result = result.where((f) => _fuzzyMatch(f.searchableText, _searchQuery)).toList();
    }
    if (_typeFilter.isNotEmpty) {
      result = result.where((f) => _typeFilter.contains(f.type)).toList();
    }
    return result;
  }

  /// Grouped by day, filtered
  Map<String, List<SharedFile>> get groupedByDay {
    final source = (isSearching || hasTypeFilter) ? filteredFiles : _files;
    final map = <String, List<SharedFile>>{};
    for (final f in source) {
      map.putIfAbsent(f.displayDate, () => []).add(f);
    }
    final sortedKeys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return {
      for (final k in sortedKeys)
        k: map[k]!..sort((a, b) => b.receivedAt.compareTo(a.receivedAt))
    };
  }

  List<SharedFile> filesForDate(String date) =>
      _files.where((f) => f.displayDate == date).toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

  // ===== Search =====

  void setSearchQuery(String query) {
    _searchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  /// Fuzzy search: query chars must appear in order in target
  /// Supports multi-term (space separated, AND logic)
  static bool _fuzzyMatch(String text, String query) {
    final lower = text.toLowerCase();
    final terms = query.split(' ').where((t) => t.isNotEmpty);
    for (final term in terms) {
      if (!_termMatch(lower, term)) return false;
    }
    return true;
  }

  static bool _termMatch(String text, String term) {
    // Exact substring match has priority
    if (text.contains(term)) return true;
    // Fuzzy: all chars in order
    int ti = 0;
    for (int i = 0; i < text.length && ti < term.length; i++) {
      if (text[i] == term[ti]) ti++;
    }
    return ti == term.length;
  }

  // ===== Type filter =====

  void toggleTypeFilter(SharedFileType type) {
    if (_typeFilter.contains(type)) {
      _typeFilter.remove(type);
    } else {
      _typeFilter.add(type);
    }
    notifyListeners();
  }

  void setTypeFilter(Set<SharedFileType> types) {
    _typeFilter = Set.from(types);
    notifyListeners();
  }

  void clearTypeFilter() {
    _typeFilter = {};
    notifyListeners();
  }

  // ===== Update metadata =====

  void updateTags(String fileId, List<String> tags) {
    final idx = _files.indexWhere((f) => f.id == fileId);
    if (idx == -1) return;
    _files[idx] = _files[idx].copyWith(tags: tags);
    _persist();
    notifyListeners();
  }

  void updateDescription(String fileId, String? description) {
    final idx = _files.indexWhere((f) => f.id == fileId);
    if (idx == -1) return;
    _files[idx] = _files[idx].copyWith(
      description: description,
      clearDescription: description == null,
    );
    _persist();
    notifyListeners();
  }

  /// Get unique tags across all files (sorted by frequency desc)
  List<TagCount> get allTags {
    final counts = <String, int>{};
    for (final f in _files) {
      for (final t in f.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => TagCount(e.key, e.value)).toList();
  }

  // ===== Ingest =====

  Future<void> ingestText(String text) async {
    _loading = true;
    notifyListeners();
    try {
      final isUrl = Uri.tryParse(text)?.hasScheme == true &&
          text.startsWith('http');
      var file = await FileHandler.handleSharedFile(
        textContent: text,
        mimeType: isUrl ? 'text/uri-list' : 'text/plain',
      );
      file = file.copyWith(
        description: text.length > 100 ? '${text.substring(0, 100)}...' : text,
        tags: ['文本'],
      );
      _files.insert(0, file);
      await _persist();
      _uploadToS3(file);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> ingestFile(String path, {String? mimeType}) async {
    _loading = true;
    notifyListeners();
    try {
      var file =
          await FileHandler.handleSharedFile(sharedPath: path, mimeType: mimeType);
      file = file.copyWith(
        description: file.name,
        tags: [file.type.label],
      );
      _files.removeWhere((f) => f.localPath == file.localPath && f.id != file.id);
      _files.insert(0, file);
      await _persist();
      _uploadToS3(file);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> ingestMultipleFiles(
    List<String> paths, {
    String? mimeType,
  }) async {
    _loading = true;
    notifyListeners();
    try {
      final results =
          await FileHandler.handleMultipleFiles(paths, mimeType: mimeType);
      for (var f in results) {
        f = f.copyWith(
          description: f.name,
          tags: [f.type.label],
        );
        _files.removeWhere((x) => x.localPath == f.localPath && x.id != f.id);
        _files.insert(0, f);
        _uploadToS3(f);
      }
      await _persist();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ===== S3 Sync =====

  Future<void> _uploadToS3(SharedFile file) async {
    debugPrint('[S3] _uploadToS3: id=${file.id} path=${file.localPath} s3Key=${file.s3Key} error=${file.uploadError}');
    final idx = _files.indexWhere((f) => f.id == file.id);
    if (idx == -1) return;

    // If has s3Key but error, retry upload (s3Key might be stale)
    if (file.s3Key != null && file.uploadError != null) {
      debugPrint('[S3] retrying upload for ${file.id} (had error, s3Key=${file.s3Key})');
      // Don't return — fall through to re-upload
    } else if (file.s3Key != null) {
      debugPrint('[S3] skip: already uploaded without error');
      return;
    }

    // For text-only files, recreate local file from textContent if missing
    String? uploadPath = file.localPath;
    if (uploadPath == null || !File(uploadPath).existsSync()) {
      if (file.textContent != null && uploadPath != null) {
        File(uploadPath).parent.createSync(recursive: true);
        File(uploadPath).writeAsStringSync(file.textContent!, flush: true);
        debugPrint('[S3] recreated text file at $uploadPath');
      } else {
        debugPrint('[S3] cannot upload: file missing and no text content');
        _files[idx] = _files[idx].copyWith(clearUploadProgress: true, uploadError: '源文件已删除');
        notifyListeners();
        return;
      }
    }

    final s3 = S3Service();
    await s3.loadConfig();
    if (!s3.isConfigured) { debugPrint('[S3] skip: not configured'); return; }

    // Sanitize filename: ASCII only, strip special chars
    final safeName = file.name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '_');
    final truncated = safeName.length > 60 ? safeName.substring(0, 60) : safeName;
    final d = file.receivedAt.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    final dateDir = '${d.year}/${pad(d.month)}/${pad(d.day)}';
    final s3Key = 'files/$dateDir/${pad(d.hour)}_${pad(d.minute)}_${pad(d.second)}_$truncated';

    final fileSize = File(uploadPath).lengthSync();
    if (fileSize < 5 * 1024 * 1024) {
      // Small file: simple upload
      _files[idx] = _files[idx].copyWith(uploadProgress: 0.01, clearUploadError: true);
      notifyListeners();
      try {
        double lastNotified = 0;
        final uploadedKey = await s3.uploadFile(uploadPath, s3Key: s3Key, onProgress: (p) {
          _files[idx] = _files[idx].copyWith(uploadProgress: p);
          if (p >= 1.0 || p - lastNotified >= 0.02 || lastNotified == 0) { lastNotified = p; notifyListeners(); }
        });
        if (uploadedKey != null) {
          _files[idx] = _files[idx].copyWith(s3Key: uploadedKey, clearUploadProgress: true, clearUploadError: true, clearUploadId: true, uploadedParts: null);
        } else {
          _files[idx] = _files[idx].copyWith(clearUploadProgress: true, uploadError: '上传失败');
        }
        notifyListeners();
      } catch (e) {
        _files[idx] = _files[idx].copyWith(clearUploadProgress: true, uploadError: '上传异常: $e');
        notifyListeners();
      }
    } else {
      // Large file: multipart upload with resume
      await _multipartUpload(s3, idx, s3Key, uploadPath);
    }
    await _persist();
  }

  /// Multipart upload with resume for large files (>=5MB)
  Future<void> _multipartUpload(S3Service s3, int idx, String s3Key, String uploadPath) async {
    final fileBytes = await File(uploadPath).readAsBytes();
    const partSize = 5 * 1024 * 1024;
    final totalParts = (fileBytes.length / partSize).ceil();
    final file = _files[idx];

    // Resume: use saved uploadedParts from DB (more reliable than listParts)
    String? uploadId = file.uploadId;
    List<MapEntry<int, String>> existingParts = [];
    if (uploadId != null && file.uploadedParts != null) {
      try {
        final list = jsonDecode(file.uploadedParts!) as List;
        existingParts = list.map((e) => MapEntry(e['part'] as int, e['etag'] as String)).toList();
        debugPrint('[S3] resume $uploadId: ${existingParts.length}/$totalParts parts from DB');
      } catch (_) {
        // Fallback to S3 listParts if DB parse fails
        existingParts = await s3.listParts(s3Key, uploadId);
        debugPrint('[S3] resume $uploadId: ${existingParts.length}/$totalParts parts from S3');
      }
    }

    // Init if needed
    if (uploadId == null) {
      uploadId = await s3.initMultipart(s3Key);
      if (uploadId == null) { _files[idx] = _files[idx].copyWith(clearUploadProgress: true, uploadError: '初始化失败'); notifyListeners(); return; }
    }
    _files[idx] = _files[idx].copyWith(uploadId: uploadId, uploadProgress: 0.01, clearUploadError: true);
    await DatabaseService.updateFile(_files[idx]);
    debugPrint('[S3] saved uploadId=$uploadId to DB for ${_files[idx].id}');
    notifyListeners();

    // Upload missing parts
    final existingSet = existingParts.map((e) => e.key).toSet();
    final allParts = <MapEntry<int, String>>[...existingParts];
    int sentBytes = existingParts.length * partSize;

    for (int p = 1; p <= totalParts; p++) {
      if (existingSet.contains(p)) continue;
      final start = (p - 1) * partSize;
      final end = start + partSize > fileBytes.length ? fileBytes.length : start + partSize;
      final etag = await s3.uploadPart(s3Key, uploadId, p, fileBytes.sublist(start, end));
      if (etag == null) {
        _files[idx] = _files[idx].copyWith(uploadProgress: (sentBytes / fileBytes.length).clamp(0.01, 0.99), uploadError: '上传中断');
        await DatabaseService.updateFile(_files[idx]);
        notifyListeners(); return;
      }
      allParts.add(MapEntry(p, etag));
      sentBytes += end - start;
      _files[idx] = _files[idx].copyWith(
        uploadProgress: (sentBytes / fileBytes.length).clamp(0.01, 0.99),
        uploadedParts: jsonEncode(allParts.map((e) => {'part': e.key, 'etag': e.value}).toList()),
      );
      await DatabaseService.updateFile(_files[idx]); // Persist for resume
      notifyListeners();
    }

    // Complete
    if (await s3.completeMultipart(s3Key, uploadId, allParts)) {
      _files[idx] = _files[idx].copyWith(s3Key: s3Key, clearUploadProgress: true, clearUploadError: true, clearUploadId: true, uploadedParts: null);
      debugPrint('[S3] multipart done');
      await DatabaseService.updateFile(_files[idx]);
      notifyListeners();
      return;
    }
    // Failed — discard broken uploadId, retry via simple upload
    debugPrint('[S3] complete failed, clearing state for retry');
    _files[idx] = _files[idx].copyWith(clearUploadProgress: true, clearUploadId: true, uploadedParts: null, uploadError: '合并失败');
    await DatabaseService.updateFile(_files[idx]);
    notifyListeners();
    await DatabaseService.updateFile(_files[idx]);
    notifyListeners();
  }

  /// Upload all files with concurrency limit of 3
  void _uploadPendingFiles() {
    debugPrint('[S3] _uploadPendingFiles called');
    final s3 = S3Service();
    s3.loadConfig().then((_) {
      debugPrint('[S3] loadConfig done, configured=${s3.isConfigured}');
      if (!s3.isConfigured) return;
      final pending = _files.where((f) => f.s3Key == null && f.localPath != null).toList();
      debugPrint('[S3] ${pending.length} files to upload (max 3 concurrent)');
      int running = 0;
      const maxConcurrent = 3;
      void startNext() {
        while (running < maxConcurrent && pending.isNotEmpty) {
          final f = pending.removeAt(0);
          running++;
          _uploadToS3(f).then((_) => running--).then((_) => startNext());
        }
      }
      startNext();
    });
  }

  Future<void> _restoreFromS3() async {
    final s3 = S3Service();
    await s3.loadConfig();
    if (!s3.isConfigured) return;
    for (int i = 0; i < _files.length; i++) {
      final f = _files[i];
      if (f.localPath == null || f.textContent != null) continue;
      if (f.s3Key == null) continue;
      if (File(f.localPath!).existsSync()) continue;
      final downloaded = await s3.downloadFile(f.s3Key!, f.localPath!);
      if (downloaded != null) {
        notifyListeners();
      }
    }
  }

  /// Retry uploading a failed file
  Future<void> retryUpload(String fileId) async {
    final idx = _files.indexWhere((f) => f.id == fileId);
    if (idx == -1) return;
    await _uploadToS3(_files[idx]);
  }

  /// Retry all failed or stuck uploads
  Future<void> retryAllFailed() async {
    for (final f in _files) {
      if (f.s3Key == null && (f.uploadError != null || f.uploadProgress != null)) {
        await _uploadToS3(f);
      }
    }
  }

  // ===== Persistence =====

  Future<void> _persist() async {
    final existing = await DatabaseService.loadFiles();
    final existingIds = existing.map((e) => e.id).toSet();
    for (final f in _files) {
      if (existingIds.contains(f.id)) {
        await DatabaseService.updateFile(f);
      } else {
        await DatabaseService.insertFile(f);
      }
      // Sync to backend (fire-and-forget)
      ApiService.instance.syncFile(f.toJson());
    }
  }

  Future<void> loadFromDisk() async {
    if (_initialized) return;
    _loading = true;
    notifyListeners();
    try {
      // Migrate from SharedPreferences to SQLite (one-time)
      final prefs = await SharedPreferences.getInstance();
      final oldJson = prefs.getString('timeline_files');
      if (oldJson != null) {
        final existing = await DatabaseService.loadFiles();
        if (existing.isEmpty) {
          final list = jsonDecode(oldJson) as List;
          for (final e in list) {
            final f = SharedFile.fromJson(e as Map<String, dynamic>);
            await DatabaseService.insertFile(f);
          }
          debugPrint('[DB] migrated ${list.length} files from SharedPrefs to SQLite');
        }
        await prefs.remove('timeline_files');
      }
      _files = await DatabaseService.loadFiles();
      debugPrint('[S3] loadFromDisk: ${_files.length} files loaded');
      // Sync all local files to backend (fire-and-forget)
      for (final f in _files) {
        ApiService.instance.syncFile(f.toJson());
      }
      _uploadPendingFiles();
      _restoreFromS3();
    } finally {
      _initialized = true;
      _loading = false;
      notifyListeners();
    }
  }

  // ===== Delete =====

  Future<void> deleteFile(SharedFile file) async {
    _files.removeWhere((f) => f.id == file.id);
    await DatabaseService.deleteFile(file.id);
    ApiService.instance.deleteFile(file.id);
    notifyListeners();
  }

  Future<void> clearAll() async {
    _files.clear();
    await DatabaseService.clearAll();
    ApiService.instance.clearAll();
    notifyListeners();
  }

  /// Clear all s3Key values so files get re-uploaded on next sync
  Future<void> resetUploadStatus() async {
    for (int i = 0; i < _files.length; i++) {
      _files[i] = _files[i].copyWith(clearS3Key: true, clearUploadProgress: true, clearUploadError: true);
      await DatabaseService.updateFile(_files[i]);
      ApiService.instance.syncFile(_files[i].toJson());
    }
    notifyListeners();
    // Trigger upload for all files
    retryAllFailed();
  }
}

class TagCount {
  final String tag;
  final int count;
  const TagCount(this.tag, this.count);
}
