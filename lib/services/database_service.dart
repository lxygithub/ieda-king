import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/shared_file.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    await _migrate(_db!);
    return _db!;
  }

  static Future<void> _migrate(Database db) async {
    // Add uploadId column if missing
    try { await db.execute('ALTER TABLE files ADD COLUMN uploadId TEXT'); } catch (_) {}
    try { await db.execute('ALTER TABLE files ADD COLUMN uploadedParts TEXT'); } catch (_) {}
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'share_timeline.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE files (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            localPath TEXT,
            textContent TEXT,
            sourceUri TEXT,
            receivedAt TEXT NOT NULL,
            mimeType TEXT,
            fileSize INTEGER NOT NULL DEFAULT 0,
            s3Key TEXT,
            uploadProgress REAL,
            uploadError TEXT,
            uploadId TEXT,
            uploadedParts TEXT,
            description TEXT,
            tags TEXT NOT NULL DEFAULT '[]'
          )
        ''');
      },
    );
  }

  static SharedFile _rowToFile(Map<String, dynamic> row) => SharedFile(
        id: row['id'] as String,
        name: row['name'] as String,
        type: SharedFileType.values.byName(row['type'] as String),
        localPath: row['localPath'] as String?,
        textContent: row['textContent'] as String?,
        sourceUri: row['sourceUri'] as String?,
        receivedAt: DateTime.parse(row['receivedAt'] as String),
        mimeType: row['mimeType'] as String?,
        fileSize: row['fileSize'] as int? ?? 0,
        s3Key: row['s3Key'] as String?,
        uploadProgress: (row['uploadProgress'] as num?)?.toDouble(),
        uploadError: row['uploadError'] as String?,
        uploadId: row['uploadId'] as String?,
        uploadedParts: row['uploadedParts'] as String?,
        tags: (jsonDecode(row['tags'] as String) as List).cast<String>(),
        description: row['description'] as String?,
      );

  static Map<String, dynamic> _fileToRow(SharedFile f) => {
        'id': f.id,
        'name': f.name,
        'type': f.type.name,
        'localPath': f.localPath,
        'textContent': f.textContent,
        'sourceUri': f.sourceUri,
        'receivedAt': f.receivedAt.toIso8601String(),
        'mimeType': f.mimeType,
        'fileSize': f.fileSize,
        's3Key': f.s3Key,
        'uploadProgress': f.uploadProgress,
        'uploadError': f.uploadError,
        'uploadId': f.uploadId,
        'uploadedParts': f.uploadedParts,
        'tags': jsonEncode(f.tags),
        'description': f.description,
      };

  /// Load all files from DB, newest first
  static Future<List<SharedFile>> loadFiles() async {
    final db = await database;
    final rows = await db.query('files', orderBy: 'receivedAt DESC');
    return rows.map(_rowToFile).toList();
  }

  /// Insert a file (skip if id exists)
  static Future<void> insertFile(SharedFile file) async {
    final db = await database;
    await db.insert('files', _fileToRow(file),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Batch insert multiple files
  static Future<void> insertFiles(List<SharedFile> files) async {
    final db = await database;
    final batch = db.batch();
    for (final f in files) {
      batch.insert('files', _fileToRow(f),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  /// Update a file by id
  static Future<void> updateFile(SharedFile file) async {
    final db = await database;
    await db.update('files', _fileToRow(file),
        where: 'id = ?', whereArgs: [file.id]);
  }

  /// Delete a file by id
  static Future<void> deleteFile(String id) async {
    final db = await database;
    await db.delete('files', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete all files
  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('files');
  }

  /// Get file count
  static Future<int> fileCount() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM files')) ?? 0;
  }
}
