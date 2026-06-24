import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shared_file.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
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
        _uploadViaApi(f);
      }
      await _persist();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ===== API Upload (replaces direct S3 upload) =====

  /// Upload file binary through the API. API stores to S3 and returns s3Key.
  Future<void> _uploadViaApi(SharedFile file) async {
    final idx = _files.indexWhere((f) => f.id == file.id);
    if (idx == -1) return;

    // Already uploaded
    if (file.s3Key != null) return;

    // No local file to upload (metadata-only sync already done via _persist)
    final localPath = file.localPath;
    if (localPath == null || !File(localPath).existsSync()) return;

    _files[idx] = _files[idx].copyWith(uploadProgress: 0.5);
    notifyListeners();

    try {
      final result = await ApiService.instance.uploadFile(
        file.localPath!,
        fileId: file.id,
        name: file.name,
        type: file.type.label,
        mimeType: file.mimeType,
      );
      _files[idx] = _files[idx].copyWith(
        s3Key: result['s3Key'],
        clearUploadProgress: true,
      );
      debugPrint('[API] upload done: ${file.id} -> ${result['s3Key']}');
    } catch (e) {
      debugPrint('[API] upload error: $e');
      _files[idx] = _files[idx].copyWith(
        clearUploadProgress: true,
        uploadError: '上传失败: $e',
      );
    }
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
      // Sync metadata to backend (fire-and-forget)
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
      debugPrint('[API] loadFromDisk: ${_files.length} files loaded');
      // Sync metadata to backend (fire-and-forget)
      for (final f in _files) {
        ApiService.instance.syncFile(f.toJson());
      }
      // Upload pending files via API
      for (final f in _files) {
        _uploadViaApi(f);
      }
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

  /// Clear all s3Key values so files get re-uploaded
  Future<void> resetUploadStatus() async {
    for (int i = 0; i < _files.length; i++) {
      _files[i] = _files[i].copyWith(clearS3Key: true, clearUploadProgress: true, clearUploadError: true);
      await DatabaseService.updateFile(_files[i]);
      ApiService.instance.syncFile(_files[i].toJson());
    }
    notifyListeners();
    retryAllFailed();
  }
}

class TagCount {
  final String tag;
  final int count;
  const TagCount(this.tag, this.count);
}
