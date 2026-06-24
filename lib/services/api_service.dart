import 'dart:convert';

import 'package:http/http.dart' as http;

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

  // ========== Auth ==========

  Future<Map<String, dynamic>> register(
      String username, String password) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 201) return jsonDecode(resp.body) as Map<String, dynamic>;
    final detail = _detail(resp);
    throw ApiException(resp.statusCode, detail);
  }

  Future<Map<String, dynamic>> login(
      String username, String password) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    final detail = _detail(resp);
    throw ApiException(resp.statusCode, detail);
  }

  // ========== Account management ==========

  Future<Map<String, dynamic>> changePassword(
      String oldPassword, String newPassword) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/auth/change-password'),
          headers: _headers,
          body: jsonEncode(
              {'old_password': oldPassword, 'new_password': newPassword}),
        )
        .timeout(const Duration(seconds: 15));
    _checkAuth(resp);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _detail(resp));
  }

  Future<Map<String, dynamic>> changeUsername(String newUsername) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/auth/change-username'),
          headers: _headers,
          body: jsonEncode({'new_username': newUsername}),
        )
        .timeout(const Duration(seconds: 15));
    _checkAuth(resp);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _detail(resp));
  }

  // ========== Upload ==========

  /// Upload file binary to API. API uploads to S3, returns s3Key.
  Future<Map<String, dynamic>> uploadFile(
    String filePath, {
    required String fileId,
    required String name,
    required String type,
    String? mimeType,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/files/upload'),
    );
    // Auth header
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.fields['file_id'] = fileId;
    request.fields['name'] = name;
    request.fields['type'] = type;
    request.fields['mimeType'] = mimeType ?? 'application/octet-stream';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamedResp = await request.send().timeout(const Duration(minutes: 5));
    final resp = await http.Response.fromStream(streamedResp);
    _checkAuth(resp);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    // 502 = S3 upload failed on server
    throw ApiException(resp.statusCode, _detail(resp));
  }

  // ========== Files ==========

  Future<List<Map<String, dynamic>>> getFiles() async {
    final resp = await http
        .get(Uri.parse('$baseUrl/api/files'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    _checkAuth(resp);
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      return (body['files'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
    }
    throw ApiException(resp.statusCode, _detail(resp));
  }

  Future<Map<String, dynamic>> syncFile(
      Map<String, dynamic> fileData) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/files/sync'),
          headers: _headers,
          body: jsonEncode(fileData),
        )
        .timeout(const Duration(seconds: 30));
    _checkAuth(resp);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _detail(resp));
  }

  Future<void> deleteFile(String id) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/files/delete'),
          headers: _headers,
          body: jsonEncode({'id': id}),
        )
        .timeout(const Duration(seconds: 10));
    _checkAuth(resp);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _detail(resp));
    }
  }

  Future<void> clearAll() async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/files/clear'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));
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
