import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shared_file.dart';
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
    if (file.localPath == null || file.textContent != null) return;
    if (file.s3Key != null) return; // already uploaded
    final s3 = S3Service();
    await s3.loadConfig();
    if (!s3.isConfigured) return;

    final idx = _files.indexWhere((f) => f.id == file.id);
    if (idx == -1) return;

    // Mark as uploading
    _files[idx] = _files[idx].copyWith(uploadProgress: 0.01, uploadError: null);
    notifyListeners();

    // Generate content-hash-based S3 key for dedup
    final fileBytes = await File(file.localPath!).readAsBytes();
    final hash = sha256.convert(fileBytes).toString();
    final s3Key = 'files/$hash';
    try {
      // Check if same content already exists on S3
      if (await s3.fileExists(s3Key)) {
        _files[idx] = _files[idx].copyWith(
          s3Key: s3Key,
          uploadProgress: null,
          uploadError: null,
        );
        await _persist();
        notifyListeners();
        return;
      }
      final uploadedKey = await s3.uploadFile(file.localPath!, s3Key: s3Key);
      if (uploadedKey != null) {
        _files[idx] = _files[idx].copyWith(
          s3Key: uploadedKey,
          uploadProgress: null,
          uploadError: null,
        );
      } else {
        _files[idx] = _files[idx].copyWith(
          uploadProgress: null,
          uploadError: '上传失败',
        );
      }
    } catch (e) {
      _files[idx] = _files[idx].copyWith(
        uploadProgress: null,
        uploadError: '上传异常: $e',
      );
    }
    await _persist();
    notifyListeners();
  }

  /// Upload all existing files that don't have an s3Key yet
  void _uploadPendingFiles() {
    final s3 = S3Service();
    s3.loadConfig().then((_) {
      if (!s3.isConfigured) return;
      for (final f in _files) {
        if (f.s3Key != null) continue;
        if (f.localPath == null || f.textContent != null) continue;
        if (!File(f.localPath!).existsSync()) continue;
        // Fire and forget
        _uploadToS3(f);
      }
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

  /// Retry all failed uploads
  Future<void> retryAllFailed() async {
    for (final f in _files) {
      if (f.uploadError != null && f.s3Key == null) {
        await _uploadToS3(f);
      }
    }
  }

  // ===== Persistence =====

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_files.map((f) => f.toJson()).toList());
    await prefs.setString('timeline_files', json);
  }

  Future<void> loadFromDisk() async {
    if (_initialized) return;
    _loading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('timeline_files');
      if (json != null) {
        final list = jsonDecode(json) as List;
        _files = list
            .map((e) => SharedFile.fromJson(e as Map<String, dynamic>))
            .where((f) {
          if (f.localPath != null && f.textContent == null) {
            if (File(f.localPath!).existsSync()) return true;
            // Local file missing — try S3 if we have an s3Key
            if (f.s3Key != null) return true;
            return false;
          }
          return true;
        }).toList();
        _files.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      }
      // Upload existing files that haven't been synced yet
      _uploadPendingFiles();
      // Try to restore missing files from S3
      _restoreFromS3();
    } finally {
      _initialized = true;
      _loading = false;
      notifyListeners();
    }
  }

  // ===== Delete (record only, keep local files) =====

  Future<void> deleteFile(SharedFile file) async {
    _files.removeWhere((f) => f.id == file.id);
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _files.clear();
    await _persist();
    notifyListeners();
  }
}

class TagCount {
  final String tag;
  final int count;
  const TagCount(this.tag, this.count);
}
