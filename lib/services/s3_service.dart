import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:minio/minio.dart';
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
    // Minio expects just host:port, no protocol prefix
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

  /// Upload file using Minio. Returns s3Key on success.
  Future<String?> uploadFile(String localPath, {String? s3Key, void Function(double)? onProgress}) async {
    if (_minio == null) return null;
    final file = File(localPath);
    if (!await file.exists()) return null;

    final key = s3Key ?? generateKey(DateTime.now(), '_${file.uri.pathSegments.last}');
    final bytes = await file.readAsBytes();
    debugPrint('[S3] minio uploading ${key} (${bytes.length} bytes)');
    onProgress?.call(0.1);

    // Split into 1MB chunks for stream to work better with Minio internals
    const chunkSize = 1024 * 1024;
    final chunks = <Uint8List>[];
    for (int i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize) < bytes.length ? i + chunkSize : bytes.length;
      chunks.add(bytes.sublist(i, end));
    }
    debugPrint('[S3] minio upload ${chunks.length} chunks');

    try {
      await _minio!.putObject(
        _config!.bucket,
        key,
        Stream.fromIterable(chunks),
        size: bytes.length,
        onProgress: (sent) {
          if (bytes.isNotEmpty) {
            final p = 0.1 + 0.85 * (sent / bytes.length);
            onProgress?.call(p.clamp(0.1, 1.0));
          }
        },
      );
      onProgress?.call(1.0);
      debugPrint('[S3] minio upload success');
      return key;
    } catch (e, s) {
      debugPrint('[S3] minio upload error: $e\n$s');
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
}
