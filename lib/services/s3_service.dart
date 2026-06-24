import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:minio/minio.dart';
// ignore: implementation_imports
import 'package:minio/src/minio_models_generated.dart' show CompletedPart;
import 'package:shared_preferences/shared_preferences.dart';

class S3Config {
  final String endpoint;
  final int port;
  final String accessKey;
  final String secretKey;
  final String bucket;
  final String region;

  const S3Config({
    required this.endpoint,
    required this.port,
    required this.accessKey,
    required this.secretKey,
    required this.bucket,
    required this.region,
  });

  Map<String, dynamic> toMap() => {
        'endpoint': endpoint,
        'port': port,
        'accessKey': accessKey,
        'secretKey': secretKey,
        'bucket': bucket,
        'region': region,
      };

  factory S3Config.fromMap(Map<String, dynamic> map) => S3Config(
        endpoint: map['endpoint'] as String,
        port: map['port'] as int? ?? 13900,
        accessKey: map['accessKey'] as String,
        secretKey: map['secretKey'] as String,
        bucket: map['bucket'] as String,
        region: map['region'] as String,
      );
}

class S3Service {
  static Minio? _minio;
  static S3Config? _config;

  bool get isConfigured => _config != null;

  Future<void> loadConfig() async {
    if (_minio != null) return;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('s3_config');
    if (json != null) {
      _config = S3Config.fromMap(jsonDecode(json) as Map<String, dynamic>);
      _initMinio();
    }
  }

  Future<void> saveConfig(S3Config config) async {
    _config = config;
    _initMinio();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('s3_config', jsonEncode(config.toMap()));
  }

  void _initMinio() {
    if (_config == null) return;
    var ep = _config!.endpoint;
    if (ep.startsWith('http://')) ep = ep.substring(7);
    if (ep.startsWith('https://')) ep = ep.substring(8);
    ep = ep.split('/')[0];
    _minio = Minio(
      endPoint: ep,
      port: _config!.port,
      accessKey: _config!.accessKey,
      secretKey: _config!.secretKey,
      useSSL: false,
      region: _config!.region,
    );
  }

  static String generateKey(DateTime date, String originalName) {
    final d = date.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    final ts = '${pad(d.hour)}_${pad(d.minute)}_${pad(d.second)}';
    return 'files/${d.year}/${pad(d.month)}/${pad(d.day)}/$ts$originalName';
  }

  /// Upload file via Minio. Returns s3Key on success.
  Future<String?> uploadFile(String localPath, {String? s3Key, void Function(double)? onProgress}) async {
    if (_minio == null) return null;
    final file = File(localPath);
    if (!await file.exists()) return null;

    final key = s3Key ?? generateKey(DateTime.now(), '_${file.uri.pathSegments.last}');
    final bytes = await file.readAsBytes();

    const chunkSize = 1024 * 1024;
    final chunks = <Uint8List>[];
    for (int i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize) < bytes.length ? i + chunkSize : bytes.length;
      chunks.add(bytes.sublist(i, end));
    }

    onProgress?.call(0.1);
    try {
      await _minio!.putObject(
        _config!.bucket, key, Stream.fromIterable(chunks),
        size: bytes.length,
        onProgress: (sent) {
          if (bytes.isNotEmpty) {
            onProgress?.call((0.1 + 0.85 * (sent / bytes.length)).clamp(0.1, 1.0));
          }
        },
      );
      onProgress?.call(1.0);
      return key;
    } catch (e, s) {
      debugPrint('[S3] upload error: $e\n$s');
      return null;
    }
  }

  Future<String?> downloadFile(String s3Key, String localPath) async {
    if (_minio == null) return null;
    try {
      final stream = await _minio!.getObject(_config!.bucket, s3Key);
      final file = File(localPath);
      await file.parent.create(recursive: true);
      final bytes = await stream.reduce((a, b) => a + b);
      await file.writeAsBytes(bytes, flush: true);
      return localPath;
    } catch (e) {
      debugPrint('[S3] download error: $e');
      return null;
    }
  }

  Future<bool> fileExists(String s3Key) async {
    if (_minio == null) return false;
    try {
      await _minio!.statObject(_config!.bucket, s3Key);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ===== Multipart upload (resume support) =====

  AWSSigV4Signer _buildSigner() {
    return AWSSigV4Signer(
      credentialsProvider: AWSCredentialsProvider(
        AWSCredentials(_config!.accessKey, _config!.secretKey),
      ),
    );
  }

  AWSCredentialScope _scope() => AWSCredentialScope(
        region: _config!.region,
        service: AWSService.s3,
        dateTime: AWSDateTime.now(),
      );

  String _host() => '${_config!.endpoint}:${_config!.port}';

  Uri _partUri(String s3Key, String uploadId, int partNumber) {
    return Uri.parse('http://${_host()}/${_config!.bucket}/$s3Key?partNumber=$partNumber&uploadId=$uploadId');
  }

  /// Initiate multipart upload
  Future<String?> initMultipart(String s3Key) async {
    if (_minio == null) return null;
    try {
      final id = await _minio!.initiateNewMultipartUpload(_config!.bucket, s3Key, null);
      debugPrint('[S3] multipart initiated: $id');
      return id;
    } catch (e) { debugPrint('[S3] init multipart error: $e'); return null; }
  }

  /// Upload a single part via signed HTTP PUT
  Future<String?> uploadPart(String s3Key, String uploadId, int partNumber, List<int> data) async {
    if (_config == null) return null;
    final signer = _buildSigner();
    final uri = _partUri(s3Key, uploadId, partNumber);
    try {
      final req = AWSHttpRequest(method: AWSHttpMethod.put, uri: uri, body: data, headers: const {'Content-Type': 'application/octet-stream'});
      final signed = await signer.sign(req, credentialScope: _scope(), serviceConfiguration: S3ServiceConfiguration());
      final resp = await http.put(signed.uri, headers: signed.headers.map((k, v) => MapEntry(k, v)), body: data).timeout(const Duration(seconds: 120));
      if (resp.statusCode == 200) {
        final etag = resp.headers['etag'] ?? '';
        debugPrint('[S3] part $partNumber done');
        return etag;
      }
      debugPrint('[S3] part $partNumber failed: ${resp.statusCode}');
    } catch (e) { debugPrint('[S3] part $partNumber error: $e'); }
    return null;
  }

  /// Complete multipart upload
  Future<bool> completeMultipart(String s3Key, String uploadId, List<MapEntry<int, String>> parts) async {
    if (_minio == null) return false;
    try {
      final completed = parts.map((p) => CompletedPart(p.value, p.key)).toList();
      await _minio!.completeMultipartUpload(_config!.bucket, s3Key, uploadId, completed);
      debugPrint('[S3] multipart completed');
      return true;
    } catch (e) { debugPrint('[S3] complete error: $e'); return false; }
  }

  /// List already-uploaded parts
  Future<List<MapEntry<int, String>>> listParts(String s3Key, String uploadId) async {
    if (_minio == null) return [];
    try {
      final parts = await _minio!.listParts(_config!.bucket, s3Key, uploadId).toList();
      return parts.where((p) => p.partNumber != null && p.eTag != null)
          .map((p) => MapEntry(p.partNumber!, p.eTag!)).toList();
    } catch (e) { debugPrint('[S3] list parts error: $e'); return []; }
  }
}
