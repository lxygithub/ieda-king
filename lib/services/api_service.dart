import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Debug builds show full auth tokens; release builds truncate.
bool _isDebug = !kReleaseMode;

/// Truncate a string for logging (hide full token, long bodies).
String _truncate(String s, {int max = 500}) =>
    s.length <= max ? s : '${s.substring(0, max)}... (${s.length} total)';

/// Thrown when the API returns HTTP 401 (token expired/invalid).
class TokenExpiredException implements Exception {
  final String message;
  TokenExpiredException([this.message = 'Token expired']);
  @override
  String toString() => 'TokenExpiredException: $message';
}

/// Thrown for non-401 API errors.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Singleton HTTP client for the backend REST API.
class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  /// Configured in main.dart — e.g. 'http://192.227.212.20:8080'
  String baseUrl = '';

  /// JWT bearer token. Set from [AuthProvider] after login/init.
  String? token;

  /// Tracks uploaded bytes for progress callbacks.
  int _uploadedBytes = 0;

  /// Called when token is expired/invalid (HTTP 401).
  /// AuthProvider registers here to force logout.
  void Function()? onTokenExpired;

  bool get isConfigured => baseUrl.isNotEmpty;

  Map<String, String> get _headers {
    final h = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  // ========== Logging ==========

  void _logReq(String method, String url, {Map<String, String>? headers, Object? body}) {
    if (!_isDebug) return;
    debugPrint('[API] >>> $method $url');
    if (headers != null && headers.isNotEmpty) {
      final h = Map<String, String>.from(headers);
      if (h.containsKey('Authorization')) {
        if (_isDebug) {
          debugPrint('[API] >>> Authorization: Bearer $token');
          h.remove('Authorization');
        } else {
          h['Authorization'] = 'Bearer ${token?.substring(0, 12)}...';
        }
      }
      if (h.isNotEmpty) debugPrint('[API] >>> headers: $h');
    }
    if (body != null) {
      final s = body is String ? body : jsonEncode(body);
      debugPrint('[API] >>> body: ${_truncate(s)}');
    }
  }

  void _logResp(http.Response resp) {
    if (!_isDebug) return;
    debugPrint('[API] <<< ${resp.statusCode} ${resp.request?.url}');
    debugPrint('[API] <<< body: ${_truncate(resp.body)}');
  }

  // ========== Auth ==========

  Future<Map<String, dynamic>> register(
      String username, String password) async {
    final url = '$baseUrl/api/auth/register';
    final body = {'username': username, 'password': password};
    _logReq('POST', url, body: body);
    final resp = await http
        .post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _logResp(resp);
    if (resp.statusCode == 201) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _detail(resp));
  }

  Future<Map<String, dynamic>> login(
      String username, String password) async {
    final url = '$baseUrl/api/auth/login';
    final body = {'username': username, 'password': password};
    _logReq('POST', url, body: body);
    final resp = await http
        .post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _logResp(resp);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _detail(resp));
  }

  // ========== Account management ==========

  Future<Map<String, dynamic>> changePassword(
      String oldPassword, String newPassword) async {
    final url = '$baseUrl/api/auth/change-password';
    final body = {'old_password': oldPassword, 'new_password': newPassword};
    _logReq('POST', url, headers: _headers, body: body);
    final resp = await http
        .post(Uri.parse(url), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _logResp(resp);
    _checkAuth(resp);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _detail(resp));
  }

  Future<Map<String, dynamic>> changeUsername(String newUsername) async {
    final url = '$baseUrl/api/auth/change-username';
    final body = {'new_username': newUsername};
    _logReq('POST', url, headers: _headers, body: body);
    final resp = await http
        .post(Uri.parse(url), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _logResp(resp);
    _checkAuth(resp);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _detail(resp));
  }

  // ========== Upload ==========

  /// Upload file binary to API. API uploads to S3, returns s3Key.
  /// [onProgress] receives bytes sent / total bytes, called during upload.
  Future<Map<String, dynamic>> uploadFile(
    String filePath, {
    required String fileId,
    required String name,
    required String type,
    String? mimeType,
    void Function(double)? onProgress,
  }) async {
    final url = '$baseUrl/api/files/upload';
    if (_isDebug) {
      debugPrint('[API] >>> POST $url (multipart)');
      debugPrint('[API] >>> fields: file_id=$fileId name=$name type=$type');
      debugPrint('[API] >>> file: $filePath');
    }

    _uploadedBytes = 0;
    final file = File(filePath);
    final fileLength = await file.length();
    final stream = file.openRead();
    final byteStream = http.ByteStream(stream.transform(
      StreamTransformer.fromHandlers(handleData: (data, sink) {
        if (onProgress != null) {
          // Track progress via a simple counter
          _uploadedBytes += data.length;
          onProgress(_uploadedBytes / fileLength);
        }
        sink.add(data);
      }),
    ));

    final request = http.MultipartRequest('POST', Uri.parse(url));
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.fields['file_id'] = fileId;
    request.fields['name'] = name;
    request.fields['type'] = type;
    request.fields['mimeType'] = mimeType ?? 'application/octet-stream';
    request.files.add(http.MultipartFile('file', byteStream, fileLength, filename: name));

    final streamedResp = await request.send().timeout(const Duration(minutes: 5));
    final resp = await http.Response.fromStream(streamedResp);
    if (_isDebug) {
      debugPrint('[API] <<< ${resp.statusCode} $url');
      debugPrint('[API] <<< body: ${_truncate(resp.body)}');
    }
    _checkAuth(resp);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw ApiException(resp.statusCode, _detail(resp));
  }

  // ========== Chunked Upload (Resumable) ==========

  Future<Map<String, dynamic>> initMultipartUpload({
    required String fileId,
    required String name,
    required String type,
    String? mimeType,
    required int fileSize,
  }) async {
    final url = '$baseUrl/api/files/upload/init';
    final request = http.MultipartRequest('POST', Uri.parse(url));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['file_id'] = fileId;
    request.fields['name'] = name;
    request.fields['type'] = type;
    if (mimeType != null) request.fields['mimeType'] = mimeType;
    request.fields['file_size'] = fileSize.toString();
    final resp = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));
    _checkAuth(resp);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _detail(resp));
  }

  Future<Map<String, dynamic>> uploadPart(
    String uploadId, {
    required int partNumber,
    required String filePath,
    required int offset,
    required int length,
    void Function(double)? onProgress,
  }) async {
    final url = '$baseUrl/api/files/upload/$uploadId/part';
    final file = File(filePath).openSync();
    file.setPositionSync(offset);
    final chunk = file.readSync(length);
    file.closeSync();
    final request = http.MultipartRequest('POST', Uri.parse(url));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['part_number'] = partNumber.toString();

    if (onProgress != null) {
      // Wrap bytes in a stream that reports progress
      int sent = 0;
      final controller = http.ByteStream.fromBytes(chunk);
      final progressStream = controller.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            sent += data.length;
            onProgress(sent / length);
            sink.add(data);
          },
        ),
      );
      request.files.add(http.MultipartFile('file', progressStream, length, filename: 'part_$partNumber'));
    } else {
      request.files.add(http.MultipartFile.fromBytes('file', chunk, filename: 'part_$partNumber'));
    }

    final resp = await http.Response.fromStream(await request.send().timeout(const Duration(minutes: 10)));
    _checkAuth(resp);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _detail(resp));
  }

  Future<Map<String, dynamic>> completeMultipartUpload(String uploadId) async {
    final url = '$baseUrl/api/files/upload/$uploadId/complete';
    final resp = await http.post(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 30));
    _checkAuth(resp);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _detail(resp));
  }

  Future<Map<String, dynamic>> abortMultipartUpload(String uploadId) async {
    final url = '$baseUrl/api/files/upload/$uploadId/abort';
    final resp = await http.post(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _detail(resp));
  }

  Future<List<Map<String, dynamic>>> listUploadParts(String uploadId) async {
    final url = '$baseUrl/api/files/upload/$uploadId/parts';
    final resp = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
    _checkAuth(resp);
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return (body['parts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    }
    throw ApiException(resp.statusCode, _detail(resp));
  }

  // ========== Files ==========

  /// Fetch files with pagination and filters. Returns {files: [...], total: N}.
  Future<Map<String, dynamic>> getFiles({int page = 0, int size = 20, String? startDate, String? endDate, String? type, String? search}) async {
    var url = '$baseUrl/api/files?page=$page&size=$size';
    if (startDate != null) url += '&start_date=$startDate';
    if (endDate != null) url += '&end_date=$endDate';
    if (type != null) url += '&type=$type';
    if (search != null && search.isNotEmpty) url += '&search=$search';
    _logReq('GET', url, headers: _headers);
    final resp = await http
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 30));
    _logResp(resp);
    _checkAuth(resp);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw ApiException(resp.statusCode, _detail(resp));
  }

  /// Sync file metadata to server.
  Future<Map<String, dynamic>?> syncFile(Map<String, dynamic> fileData) async {
    final url = '$baseUrl/api/files/sync';
    _logReq('POST', url, headers: _headers, body: fileData);
    try {
      final resp = await http
          .post(Uri.parse(url), headers: _headers, body: jsonEncode(fileData))
          .timeout(const Duration(seconds: 30));
      _logResp(resp);
      _checkAuth(resp);
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      if (_isDebug) debugPrint('[API] syncFile error: ${resp.statusCode} ${_detail(resp)}');
    } catch (e) {
      if (_isDebug) debugPrint('[API] syncFile exception: $e');
    }
    return null;
  }

  Future<void> deleteFile(String id) async {
    final url = '$baseUrl/api/files/delete';
    final body = {'id': id};
    _logReq('POST', url, headers: _headers, body: body);
    final resp = await http
        .post(Uri.parse(url), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
    _logResp(resp);
    _checkAuth(resp);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _detail(resp));
    }
  }

  Future<void> clearAll() async {
    final url = '$baseUrl/api/files/clear';
    _logReq('POST', url, headers: _headers);
    final resp = await http
        .post(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _logResp(resp);
    _checkAuth(resp);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _detail(resp));
    }
  }

  // ========== Helpers ==========

  /// Throw [TokenExpiredException] on 401 so the caller can redirect to login.
  void _checkAuth(http.Response resp) {
    if (resp.statusCode == 401) {
      token = null;
      onTokenExpired?.call();
      throw TokenExpiredException();
    }
  }

  static String _detail(http.Response resp) {
    try {
      final body = jsonDecode(resp.body);
      return body['detail']?.toString() ?? 'Unknown error';
    } catch (_) {
      return 'HTTP ${resp.statusCode}';
    }
  }
}
