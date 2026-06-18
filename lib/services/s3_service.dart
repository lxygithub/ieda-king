import 'dart:convert';
import 'dart:io';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class S3Config {
  final String endpoint;
  final String accessKey;
  final String secretKey;
  final String bucket;
  final String region;

  const S3Config({
    required this.endpoint,
    required this.accessKey,
    required this.secretKey,
    required this.bucket,
    required this.region,
  });

  Map<String, String> toMap() => {
        'endpoint': endpoint,
        'accessKey': accessKey,
        'secretKey': secretKey,
        'bucket': bucket,
        'region': region,
      };

  factory S3Config.fromMap(Map<String, String> map) => S3Config(
        endpoint: map['endpoint']!,
        accessKey: map['accessKey']!,
        secretKey: map['secretKey']!,
        bucket: map['bucket']!,
        region: map['region']!,
      );

  String get baseUrl =>
      endpoint.endsWith('/') ? '$endpoint$bucket' : '$endpoint/$bucket';
}

class S3Service {
  static S3Config? _globalConfig;
  static AWSSigV4Signer? _globalSigner;

  S3Config? _config;
  AWSSigV4Signer? _signer;

  bool get isConfigured => _config != null;

  Future<void> loadConfig() async {
    // Use cached global config if available
    if (_globalConfig != null) {
      _config = _globalConfig;
      _signer = _globalSigner;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('s3_config');
    if (json != null) {
      final map = Map<String, String>.from(jsonDecode(json));
      _config = S3Config.fromMap(map);
      _initSigner();
      _globalConfig = _config;
      _globalSigner = _signer;
    }
  }

  Future<void> saveConfig(S3Config config) async {
    _config = config;
    _globalConfig = config;
    _initSigner();
    _globalSigner = _signer;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('s3_config', jsonEncode(config.toMap()));
  }

  void _initSigner() {
    if (_config == null) return;
    final credentials = AWSCredentials(
      _config!.accessKey,
      _config!.secretKey,
    );
    _signer = AWSSigV4Signer(
      credentialsProvider: AWSCredentialsProvider(credentials),
    );
  }

  Uri _uri(String s3Key) => Uri.parse('${_config!.baseUrl}/$s3Key');

  AWSCredentialScope _scope() => AWSCredentialScope(
        region: _config!.region,
        service: AWSService.s3,
        dateTime: AWSDateTime.now(),
      );

  /// Upload a file to S3. Returns the s3Key on success.
  Future<String?> uploadFile(String localPath, {String? s3Key}) async {
    if (_config == null || _signer == null) return null;
    final file = File(localPath);
    if (!await file.exists()) return null;

    final key = s3Key ??
        '${DateTime.now().millisecondsSinceEpoch}_${file.uri.pathSegments.last}';
    final uri = _uri(key);
    final bytes = await file.readAsBytes();

    try {
      final request = AWSHttpRequest(
        method: AWSHttpMethod.put,
        uri: uri,
        body: bytes,
        headers: const {'Content-Type': 'application/octet-stream'},
      );
      final signed = await _signer!.sign(
        request,
        credentialScope: _scope(),
        serviceConfiguration: S3ServiceConfiguration(),
      );
      final response = await http.put(
        signed.uri,
        headers: signed.headers.map((k, v) => MapEntry(k, v)),
        body: await signed.bodyBytes as List<int>,
      );
      if (response.statusCode == 200) return key;
      debugPrint('S3 upload failed: ${response.statusCode} ${response.body}');
    } catch (e) {
      debugPrint('S3 upload error: $e');
    }
    return null;
  }

  /// Download a file from S3. Returns local path on success.
  Future<String?> downloadFile(String s3Key, String localPath) async {
    if (_config == null || _signer == null) return null;

    try {
      final request = AWSHttpRequest(
        method: AWSHttpMethod.get,
        uri: _uri(s3Key),
      );
      final signed = await _signer!.sign(
        request,
        credentialScope: _scope(),
        serviceConfiguration: S3ServiceConfiguration(),
      );
      final response = await http.get(
        signed.uri,
        headers: signed.headers.map((k, v) => MapEntry(k, v)),
      );
      if (response.statusCode == 200) {
        final file = File(localPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return localPath;
      }
    } catch (e) {
      debugPrint('S3 download error: $e');
    }
    return null;
  }

  /// Check if a file exists on S3
  Future<bool> fileExists(String s3Key) async {
    if (_config == null || _signer == null) return false;
    try {
      final request = AWSHttpRequest(
        method: AWSHttpMethod.head,
        uri: _uri(s3Key),
      );
      final signed = await _signer!.sign(
        request,
        credentialScope: _scope(),
        serviceConfiguration: S3ServiceConfiguration(),
      );
      final response = await http.head(
        signed.uri,
        headers: signed.headers.map((k, v) => MapEntry(k, v)),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
