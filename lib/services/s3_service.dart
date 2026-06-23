import 'dart:async';
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

  /// Generate date-based S3 key with original filename
  static String generateKey(DateTime date, String originalName) {
    final d = date.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    final ts = '${pad(d.hour)}_${pad(d.minute)}_${pad(d.second)}';
    return 'files/${d.year}/${pad(d.month)}/${pad(d.day)}/$ts$originalName';
  }

  /// Upload a file to S3. Returns the s3Key on success.
  /// [onProgress] callback receives 0.0-1.0 during upload.
  Future<String?> uploadFile(
    String localPath, {
    String? s3Key,
    void Function(double)? onProgress,
  }) async {
    if (_config == null || _signer == null) return null;
    final file = File(localPath);
    if (!await file.exists()) return null;

    final key = s3Key ?? generateKey(DateTime.now(), '_${file.uri.pathSegments.last}');
    final uri = _uri(key);
    final bytes = await file.readAsBytes();
    debugPrint('[S3] key=$key uri=$uri');
    onProgress?.call(0.1);

    try {
      debugPrint('[S3] start uploadFile method');
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
      debugPrint('[S3] signing complete, starting upload...');
      onProgress?.call(0.2);

      // Send using regular http.put with signed body
      final client = http.Client();
      try {
        final response = await client
            .put(
              signed.uri,
              headers: signed.headers.map((k, v) => MapEntry(k, v)),
              body: await signed.bodyBytes as List<int>,
            )
            .timeout(const Duration(seconds: 60));
        debugPrint('[S3] upload response: ${response.statusCode}');
        onProgress?.call(1.0);

        if (response.statusCode == 200) {
          return key;
        }
        debugPrint('S3 upload failed: ${response.statusCode} ${response.body}');
      } finally {
        client.close();
      }
    } on TimeoutException catch (e) {
      debugPrint('[S3] timeout: $e');
    } catch (e, s) {
      debugPrint('[S3] upload error: $e\n$s');
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
      ).timeout(const Duration(seconds: 30));
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

  /// Check if a file exists on S3 using GET Range (more reliable than HEAD)
  Future<bool> fileExists(String s3Key) async {
    if (_config == null || _signer == null) return false;
    try {
      final request = AWSHttpRequest(
        method: AWSHttpMethod.get,
        uri: _uri(s3Key),
        headers: const {'Range': 'bytes=0-0'},
      );
      final signed = await _signer!.sign(
        request,
        credentialScope: _scope(),
        serviceConfiguration: S3ServiceConfiguration(),
      );
      final response = await http.get(
        signed.uri,
        headers: signed.headers.map((k, v) => MapEntry(k, v)),
      ).timeout(const Duration(seconds: 10));
      // 206 Partial Content = exists, 404 = doesn't exist
      return response.statusCode == 206 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
