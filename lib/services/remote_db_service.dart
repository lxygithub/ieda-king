import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shared_file.dart';

class MySQLConfig {
  final String host;
  final int port;
  final String user;
  final String password;
  final String database;

  const MySQLConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.database,
  });

  Map<String, String> toMap() => {
        'host': host,
        'port': port.toString(),
        'user': user,
        'password': password,
        'database': database,
      };

  factory MySQLConfig.fromMap(Map<String, String> map) => MySQLConfig(
        host: map['host']!,
        port: int.parse(map['port']!),
        user: map['user']!,
        password: map['password']!,
        database: map['database']!,
      );
}

class RemoteDbService {
  static MySQLConfig? _config;
  static MySQLConnection? _conn;
  static bool _tableChecked = false;

  static Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('mysql_config');
    if (json != null) {
      _config = MySQLConfig.fromMap(Map<String, String>.from(jsonDecode(json)));
    }
  }

  static Future<void> saveConfig(MySQLConfig config) async {
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mysql_config', jsonEncode(config.toMap()));
  }

  static bool get isConfigured => _config != null;

  static Future<MySQLConnection?> _getConn() async {
    if (_config == null) return null;
    if (_conn != null && _conn!.connected) return _conn!;
    try {
      _conn = await MySQLConnection.createConnection(
        host: _config!.host,
        port: _config!.port,
        userName: _config!.user,
        password: _config!.password,
        databaseName: _config!.database,
      );
      await _conn!.connect();
      if (!_tableChecked) {
        await _conn!.execute('''
          CREATE TABLE IF NOT EXISTS files (
            id VARCHAR(64) PRIMARY KEY,
            name TEXT NOT NULL,
            type VARCHAR(32) NOT NULL,
            localPath TEXT,
            textContent LONGTEXT,
            sourceUri TEXT,
            receivedAt VARCHAR(32) NOT NULL,
            mimeType VARCHAR(64),
            fileSize BIGINT NOT NULL DEFAULT 0,
            s3Key VARCHAR(256),
            uploadProgress DOUBLE,
            uploadError TEXT,
            description TEXT,
            tags TEXT NOT NULL DEFAULT '[]'
          )
        ''');
        _tableChecked = true;
      }
      return _conn;
    } catch (e) {
      debugPrint('[MySQL] connection failed: $e');
      return null;
    }
  }

  /// Upsert a single file to MySQL (fire-and-forget)
  static Future<void> upsertFile(SharedFile file) async {
    final conn = await _getConn();
    if (conn == null) return;
    try {
      await conn.execute(
        'REPLACE INTO files (id, name, type, localPath, textContent, sourceUri, receivedAt, mimeType, fileSize, s3Key, uploadProgress, uploadError, tags, description) '
        'VALUES (:id, :name, :type, :localPath, :textContent, :sourceUri, :receivedAt, :mimeType, :fileSize, :s3Key, :uploadProgress, :uploadError, :tags, :description)',
        {
          'id': file.id,
          'name': file.name,
          'type': file.type.name,
          'localPath': file.localPath,
          'textContent': file.textContent,
          'sourceUri': file.sourceUri,
          'receivedAt': file.receivedAt.toIso8601String(),
          'mimeType': file.mimeType,
          'fileSize': file.fileSize,
          's3Key': file.s3Key,
          'uploadProgress': file.uploadProgress,
          'uploadError': file.uploadError,
          'tags': jsonEncode(file.tags),
          'description': file.description,
        },
      );
    } catch (e) {
      debugPrint('[MySQL] upsert error: $e');
    }
  }

  /// Delete a file from MySQL
  static Future<void> deleteFile(String id) async {
    final conn = await _getConn();
    if (conn == null) return;
    try {
      await conn.execute('DELETE FROM files WHERE id = :id', {'id': id});
    } catch (e) {
      debugPrint('[MySQL] delete error: $e');
    }
  }

  /// Load all files from MySQL (returns null on failure)
  static Future<List<SharedFile>?> loadFiles() async {
    final conn = await _getConn();
    if (conn == null) return null;
    try {
      final result = await conn.execute('SELECT * FROM files ORDER BY receivedAt DESC');
      return result.rows.map((row) {
        final r = row.assoc();
        return SharedFile(
          id: r['id'] ?? '',
          name: r['name'] ?? '',
          type: SharedFileType.values.byName(r['type'] ?? 'other'),
          localPath: r['localPath'],
          textContent: r['textContent'],
          sourceUri: r['sourceUri'],
          receivedAt: DateTime.parse(r['receivedAt'] ?? DateTime.now().toIso8601String()),
          mimeType: r['mimeType'],
          fileSize: int.tryParse(r['fileSize'] ?? '0') ?? 0,
          s3Key: r['s3Key'],
          uploadProgress: double.tryParse(r['uploadProgress'] ?? ''),
          uploadError: r['uploadError'],
          tags: (jsonDecode(r['tags'] ?? '[]') as List).cast<String>(),
          description: r['description'],
        );
      }).toList();
    } catch (e) {
      debugPrint('[MySQL] load error: $e');
      return null;
    }
  }

  /// Delete all files from MySQL
  static Future<void> clearAll() async {
    final conn = await _getConn();
    if (conn == null) return;
    try {
      await conn.execute('DELETE FROM files');
    } catch (e) {
      debugPrint('[MySQL] clear error: $e');
    }
  }

  /// Close connection
  static Future<void> close() async {
    if (_conn != null) {
      await _conn!.close();
      _conn = null;
    }
  }
}
