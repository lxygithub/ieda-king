import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:mmkv/mmkv.dart';

import '../models/shared_file.dart';
import '../services/api_service.dart';
import '../services/foreground_task_handler.dart';
import '../utils/file_handler.dart';

class TimelineProvider extends ChangeNotifier {
  static const int _pageSize = 20;

  List<SharedFile> _files = [];
  final Map<String, String?> _uploadingIds = {}; // fileId -> uploadId (null=single upload)
  bool _initialized = false;
  bool _loading = false;
  bool _loadingMore = false;
  int _page = 0;
  int _totalCount = 0;
  String _searchQuery = '';
  Set<SharedFileType> _typeFilter = {};
  DateTime? _startDate;
  DateTime? _endDate;

  List<SharedFile> get files => _files;
  bool get initialized => _initialized;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _files.length < _totalCount;
  String get searchQuery => _searchQuery;
  Set<SharedFileType> get typeFilter => _typeFilter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  bool get hasDateFilter => _startDate != null || _endDate != null;

  bool get isSearching => _searchQuery.isNotEmpty;
  bool get hasTypeFilter => _typeFilter.isNotEmpty;

  /// Set date range filter and reload.
  Future<void> setDateRange(DateTime? start, DateTime? end) async {
    _startDate = start;
    _endDate = end;
    _files = [];
    _page = 0;
    _totalCount = 0;
    notifyListeners();
    await _fetchPage(0);
  }

  /// Clear date filter and reload.
  Future<void> clearDateFilter() async {
    _startDate = null;
    _endDate = null;
    _files = [];
    _page = 0;
    _totalCount = 0;
    notifyListeners();
    await _fetchPage(0);
  }

  Future<void> _fetchPage(int page) async {
    if (page == 0) {
      _loading = true;
      notifyListeners();
    } else {
      _loadingMore = true;
      notifyListeners();
    }
    try {
      final result = await ApiService.instance.getFiles(
        page: page,
        size: _pageSize,
        startDate: _startDate?.toIso8601String().substring(0, 10),
        endDate: _endDate?.toIso8601String().substring(0, 10),
        type: _typeFilter.isNotEmpty ? _typeFilter.map((t) => t.name).join(',') : null,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      final items = (result['files'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      final total = result['total'] as int? ?? items.length;
      final parsed = items.map((j) => SharedFile.fromJson(j)).toList();
      if (page == 0) {
        _files = parsed;
      } else {
        _files.addAll(parsed);
      }
      _totalCount = total;
      _page = page;
    } catch (e) {
      debugPrint('[API] fetchPage error: $e');
    } finally {
      _loading = false;
      _loadingMore = false;
      notifyListeners();
    }
  }

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

  Future<void> setSearchQuery(String query) async {
    _searchQuery = query.trim().toLowerCase();
    _files = [];
    _page = 0;
    _totalCount = 0;
    notifyListeners();
    await _fetchPage(0);
  }

  Future<void> clearSearch() async {
    _searchQuery = '';
    _files = [];
    _page = 0;
    _totalCount = 0;
    notifyListeners();
    await _fetchPage(0);
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

  Future<void> toggleTypeFilter(SharedFileType type) async {
    if (_typeFilter.contains(type)) {
      _typeFilter.remove(type);
    } else {
      _typeFilter.add(type);
    }
    _files = [];
    _page = 0;
    _totalCount = 0;
    notifyListeners();
    await _fetchPage(0);
  }

  Future<void> setTypeFilter(Set<SharedFileType> types) async {
    _typeFilter = Set.from(types);
    _files = [];
    _page = 0;
    _totalCount = 0;
    notifyListeners();
    await _fetchPage(0);
  }

  Future<void> clearTypeFilter() async {
    _typeFilter = {};
    _files = [];
    _page = 0;
    _totalCount = 0;
    notifyListeners();
    await _fetchPage(0);
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
      ApiService.instance.syncFile(file.toSyncJson());
      _uploadViaApi(file);
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
      ApiService.instance.syncFile(file.toSyncJson());
      _uploadViaApi(file);
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
        ApiService.instance.syncFile(f.toSyncJson());
        _uploadViaApi(f);
      }
      await _persist();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ===== Foreground Service (background upload + notification) =====

  int get _activeUploadCount => _uploadingIds.length;

  /// Start foreground service on first upload, refresh notification.
  void _ensureUploadService() {
    if (_activeUploadCount == 1) {
      FlutterForegroundTask.startService(
        callback: uploadForegroundTaskCallback,
        notificationTitle: 'Uploading...',
        notificationText: 'Starting...',
      );
    }
    _refreshUploadNotification();
  }

  /// Refresh notification progress from all active uploads.
  void _refreshUploadNotification() {
    if (_activeUploadCount == 0) return;

    double totalProgress = 0;
    int trackedCount = 0;
    String? firstName;

    for (final f in _files) {
      if (_uploadingIds.containsKey(f.id)) {
        if (f.uploadProgress != null) {
          totalProgress += f.uploadProgress!;
          trackedCount++;
        }
        firstName ??= f.name;
      }
    }

    final avgProgress = trackedCount > 0 ? totalProgress / trackedCount : 0.0;
    final pct = (avgProgress * 100).toInt();
    final title = _activeUploadCount == 1
        ? 'Uploading ${firstName ?? "file"}'
        : 'Uploading $_activeUploadCount files';
    final text = '$pct%';

    FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  /// Stop foreground service when queue is empty.
  void _checkStopService() {
    if (_activeUploadCount == 0) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Upload complete',
        notificationText: 'All files uploaded',
      );
      // Brief delay so user sees "complete", then dismiss
      Future.delayed(const Duration(seconds: 2), () {
        if (_activeUploadCount == 0) {
          FlutterForegroundTask.stopService();
        }
      });
    }
  }

  // ===== API Upload with chunked resume support =====

  static const int _chunkSize = 50 * 1024 * 1024; // 50MB (reduced Garage compaction pressure)

  Future<void> _uploadViaApi(SharedFile file) async {
    if (_uploadingIds.containsKey(file.id)) return;
    _uploadingIds[file.id] = null;
    final idx = _files.indexWhere((f) => f.id == file.id);
    if (idx == -1) { _uploadingIds.remove(file.id); return; }
    if (file.s3Key != null) { _uploadingIds.remove(file.id); return; }
    final localPath = file.localPath;
    if (localPath == null || !File(localPath).existsSync()) {
      _uploadingIds.remove(file.id);
      if (idx < _files.length) {
        _files[idx] = _files[idx].copyWith(uploadError: '本地文件已删除，无法上传');
        notifyListeners();
      }
      return;
    }

    _ensureUploadService();

    final fp = File(localPath);
    final fileSize = await fp.length();

    _files[idx] = _files[idx].copyWith(uploadProgress: 0.0);
    notifyListeners();

    try {
      // Small files: simple upload
      if (fileSize < _chunkSize) {
        final result = await ApiService.instance.uploadFile(
          localPath, fileId: file.id, name: file.name,
          type: file.type.label, mimeType: file.mimeType,
          onProgress: (p) {
            _files[idx] = _files[idx].copyWith(uploadProgress: p);
            notifyListeners();
            _refreshUploadNotification();
          },
        );
        final currentIdx = _files.indexWhere((f) => f.id == file.id);
        if (currentIdx >= 0) {
          _files[currentIdx] = _files[currentIdx].copyWith(s3Key: result['s3Key'], clearUploadProgress: true);
        }
        ApiService.instance.syncFile(file.toSyncJson());
        debugPrint('[API] upload done: ${file.id} -> ${result['s3Key']}');
        await _persist();
        _uploadingIds.remove(file.id);
        _refreshUploadNotification();
        _checkStopService();
        notifyListeners();
        return;
      }

      // Large files: chunked upload with resume
      final api = ApiService.instance;
      final mmkv = MMKV.defaultMMKV();
      final uploadKey = 'upload_id_${file.id}';
      final fileSizeMb = (fileSize / 1048576).toStringAsFixed(1);
      debugPrint('[chunk] start: ${file.name} size=${fileSizeMb}MB id=${file.id}');

      // Try to resume existing upload
      var uploadId = mmkv.decodeString(uploadKey);
      Set<int> doneParts = {};

      if (uploadId != null) {
        try {
          final parts = await api.listUploadParts(uploadId);
          for (final p in parts) {
            doneParts.add(p['part_number'] as int);
          }
          debugPrint('[chunk] resume upload_id=$uploadId ${doneParts.length} parts already done');
        } catch (_) {
          debugPrint('[chunk] resume failed, start fresh');
          uploadId = null;
        }
      }

      if (uploadId == null) {
        final init = await api.initMultipartUpload(
          fileId: file.id, name: file.name,
          type: file.type.label, mimeType: file.mimeType,
          fileSize: fileSize,
        );
        uploadId = init['upload_id'] as String;
        _uploadingIds[file.id] = uploadId;
        mmkv.encodeString(uploadKey, uploadId);
        debugPrint('[chunk] init upload_id=$uploadId');
      }
      final totalChunks = (fileSize / _chunkSize).ceil();
      debugPrint('[chunk] total ${totalChunks}x${_chunkSize ~/ 1048576}MB parts, done=${doneParts.length}');

      for (int i = 0; i < totalChunks; i++) {
        final partNum = i + 1;
        if (doneParts.contains(partNum)) {
          debugPrint('[chunk] part $partNum/$totalChunks skipped (already done)');
          continue;
        }

        final offset = i * _chunkSize;
        final length = (i == totalChunks - 1) ? fileSize - offset : _chunkSize;
        final partMb = (length / 1048576).toStringAsFixed(1);

        // Retry failed chunk up to 3 times
        for (int retry = 0; retry < 3; retry++) {
          try {
            debugPrint('[chunk] uploading part $partNum/$totalChunks (${partMb}MB) try=${retry + 1}');
            final sw = Stopwatch()..start();
            await api.uploadPart(uploadId, partNumber: partNum, filePath: localPath, offset: offset, length: length);
            sw.stop();
            debugPrint('[chunk] part $partNum/$totalChunks done in ${sw.elapsedMilliseconds}ms');
            break;
          } catch (e) {
            if (retry == 2) {
              debugPrint('[chunk] part $partNum FAILED after 3 retries: $e');
              rethrow;
            }
            debugPrint('[chunk] part $partNum error (try ${retry + 1}): $e');
            await Future.delayed(Duration(seconds: 2 * (retry + 1)));
          }
        }
        _files[idx] = _files[idx].copyWith(uploadProgress: (i + 1) / totalChunks);
        notifyListeners();
        _refreshUploadNotification();
      }

      debugPrint('[chunk] completing upload...');
      final result = await api.completeMultipartUpload(uploadId);
      mmkv.removeValue(uploadKey);
      final curIdx = _files.indexWhere((f) => f.id == file.id);
      if (curIdx >= 0) {
        _files[curIdx] = _files[curIdx].copyWith(s3Key: result['s3Key'], clearUploadProgress: true);
      }
      ApiService.instance.syncFile(file.toSyncJson());
      debugPrint('[chunk] DONE: ${file.id} -> ${result['s3Key']}');
    } catch (e) {
      debugPrint('[API] upload error: $e');
      if (idx < _files.length && _files[idx].id == file.id) {
        _files[idx] = _files[idx].copyWith(clearUploadProgress: true, uploadError: '上传失败: $e');
      }
    }
    _uploadingIds.remove(file.id);
    _refreshUploadNotification();
    _checkStopService();
    await _persist();
    notifyListeners();
  }

  /// Retry uploading a failed file
  Future<void> retryUpload(String fileId) async {
    final idx = _files.indexWhere((f) => f.id == fileId);
    if (idx == -1) return;
    // Clear old error so UI shows progress
    _files[idx] = _files[idx].copyWith(clearUploadError: true, clearUploadProgress: true);
    notifyListeners();
    await _uploadViaApi(_files[idx]);
  }

  /// Retry all failed uploads
  Future<void> retryAllFailed() async {
    for (final f in _files) {
      if (f.s3Key == null && f.uploadError != null) {
        await _uploadViaApi(f);
      }
    }
  }

  /// Sync all local files to server (manual sync button).
  /// Persist localPath map in MMKV so restarts can re-upload pending files.
  Future<void> _persist() async {
    final mmkv = MMKV.defaultMMKV();
    final localPaths = <String, String>{};
    for (final f in _files) {
      if (f.localPath != null) {
        localPaths[f.id] = f.localPath!;
      }
    }
    mmkv.encodeString('local_paths', jsonEncode(localPaths));
  }

  Future<void> loadFromDisk() async {
    if (_initialized) return;
    _initialized = true;

    // Restore persisted localPaths into current _files before API fetch
    final mmkv = MMKV.defaultMMKV();
    final saved = mmkv.decodeString('local_paths');
    if (saved != null && saved.isNotEmpty) {
      try {
        final map = jsonDecode(saved) as Map<String, dynamic>;
        for (final entry in map.entries) {
          if (entry.value != null) {
            // Set localPath on any matching file already in _files
            final idx = _files.indexWhere((f) => f.id == entry.key);
            if (idx >= 0 && _files[idx].localPath == null) {
              _files[idx] = _files[idx].copyWith(localPath: entry.value as String);
            }
          }
        }
      } catch (_) {}
    }

    // Fetch from API on startup
    await fetchFromApi();
  }

  /// Fetch first page from API, replace local cache.
  Future<void> fetchFromApi() async {
    _loading = true;
    notifyListeners();
    try {
      // Preserve local paths from current files
      final localPaths = <String, String>{};
      for (final f in _files) {
        if (f.localPath != null) localPaths[f.id] = f.localPath!;
      }
      // Fetch page 0
      _files = [];
      _page = 0;
      _totalCount = 0;
      await _fetchPage(0);
      // Restore local paths and trigger upload for pending files
      for (int i = 0; i < _files.length; i++) {
        if (_files[i].localPath == null && localPaths.containsKey(_files[i].id)) {
          _files[i] = _files[i].copyWith(localPath: localPaths[_files[i].id]);
        }
        // Auto-upload files that have localPath but no s3Key
        if (_files[i].s3Key == null && _files[i].localPath != null) {
          _uploadViaApi(_files[i]);
        }
      }
    } on TokenExpiredException {
      _loading = false;
      notifyListeners();
      return;
    } catch (e) {
      debugPrint('[API] fetchFromApi error: $e');
      _files = [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Load more pages from API.
  Future<void> loadMore() async {
    if (_loadingMore || !hasMore) return;
    _loadingMore = true;
    notifyListeners();
    await _fetchPage(_page + 1);
    _loadingMore = false;
    notifyListeners();
  }

  // ===== Delete =====

  Future<void> deleteFile(SharedFile file) async {
    final uploadId = _uploadingIds[file.id];
    if (uploadId != null) {
      try { await ApiService.instance.abortMultipartUpload(uploadId); } catch (_) {}
    }
    _uploadingIds.remove(file.id);
    _files.removeWhere((f) => f.id == file.id);
    ApiService.instance.deleteFile(file.id);
    _refreshUploadNotification();
    _checkStopService();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _uploadingIds.clear();
    _files.clear();
    ApiService.instance.clearAll();
    notifyListeners();
  }

  /// Clear all s3Key values so files get re-uploaded
}

class TagCount {
  final String tag;
  final int count;
  const TagCount(this.tag, this.count);
}
