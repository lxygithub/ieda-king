import 'package:flutter/material.dart';

enum SharedFileType { image, text, document, url, video, audio, apk, other }

extension SharedFileTypeX on SharedFileType {
  String get label {
    switch (this) {
      case SharedFileType.image:
        return '图片';
      case SharedFileType.text:
        return '文本';
      case SharedFileType.document:
        return '文档';
      case SharedFileType.url:
        return '链接';
      case SharedFileType.video:
        return '视频';
      case SharedFileType.audio:
        return '音频';
      case SharedFileType.apk:
        return 'APK';
      case SharedFileType.other:
        return '其他';
    }
  }

  IconData get icon {
    switch (this) {
      case SharedFileType.image:
        return Icons.image;
      case SharedFileType.text:
        return Icons.text_snippet;
      case SharedFileType.document:
        return Icons.description;
      case SharedFileType.url:
        return Icons.link;
      case SharedFileType.video:
        return Icons.videocam;
      case SharedFileType.audio:
        return Icons.audiotrack;
      case SharedFileType.apk:
        return Icons.android;
      case SharedFileType.other:
        return Icons.insert_drive_file;
    }
  }
}

class SharedFile {
  final String id;
  final String name;
  final String? title;
  final SharedFileType type;
  final String? localPath;
  final String? textContent;
  final String? sourceUri;
  final DateTime receivedAt;
  final String? mimeType;
  final int fileSize;
  final String? s3Key;
  final double? uploadProgress; // null=done/idle, 0.0-1.0=uploading
  final String? uploadError;
  final String? uploadId; // Minio multipart upload ID (for resume)
  final String? uploadedParts; // JSON: [{"part":1,"etag":"..."}]
  final List<String> tags;
  final String? description;
  final String? thumbS3Key;

  const SharedFile({
    required this.id,
    required this.name,
    this.title,
    required this.type,
    this.localPath,
    this.textContent,
    this.sourceUri,
    required this.receivedAt,
    this.mimeType,
    this.fileSize = 0,
    this.s3Key,
    this.uploadProgress,
    this.uploadError,
    this.uploadId,
    this.uploadedParts,
    this.tags = const [],
    this.description,
    this.thumbS3Key,
  });

  String get displayDate => receivedAt.toIso8601String().substring(0, 10);

  /// API download URL (relative). Prepend ApiService.instance.baseUrl.
  /// API thumbnail URL (relative). For list/thumb display, faster than full download.
  String get thumbUrl => '/api/files/$id/thumbnail';

  String get downloadUrl => '/api/files/$id/download';

  /// All searchable text for this file
  String get searchableText {
    final parts = <String>[name];
    if (title != null && title!.isNotEmpty) parts.add(title!);
    if (description != null) parts.add(description!);
    parts.addAll(tags);
    if (textContent != null) {
      parts.add(textContent!.length > 200
          ? textContent!.substring(0, 200)
          : textContent!);
    }
    return parts.join(' ').toLowerCase();
  }

  SharedFile copyWith({
    String? title,
    String? localPath,
    String? textContent,
    List<String>? tags,
    String? description,
    String? s3Key,
    String? thumbS3Key,
    double? uploadProgress,
    String? uploadError,
    String? uploadId,
    String? uploadedParts,
    bool clearTitle = false,
    bool clearDescription = false,
    bool clearS3Key = false,
    bool clearUploadProgress = false,
    bool clearUploadError = false,
    bool clearUploadId = false,
  }) =>
      SharedFile(
        id: id,
        name: name,
        title: clearTitle ? null : (title ?? this.title),
        type: type,
        localPath: localPath ?? this.localPath,
        textContent: textContent ?? this.textContent,
        sourceUri: sourceUri,
        receivedAt: receivedAt,
        mimeType: mimeType,
        fileSize: fileSize,
        s3Key: clearS3Key ? null : (s3Key ?? this.s3Key),
        thumbS3Key: thumbS3Key ?? this.thumbS3Key,
        uploadProgress: clearUploadProgress ? null : (uploadProgress ?? this.uploadProgress),
        uploadError: clearUploadError ? null : (uploadError ?? this.uploadError),
        uploadId: clearUploadId ? null : (uploadId ?? this.uploadId),
        uploadedParts: uploadedParts ?? this.uploadedParts,
        tags: tags ?? this.tags,
        description: clearDescription ? null : (description ?? this.description),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'title': title,
        'type': type.name,
        'localPath': localPath,
        'textContent': textContent,
        'sourceUri': sourceUri,
        'receivedAt': receivedAt.toIso8601String(),
        'mimeType': mimeType,
        'fileSize': fileSize,
        's3Key': s3Key,
        'thumbS3Key': thumbS3Key,
        'uploadProgress': uploadProgress,
        'uploadError': uploadError,
        'uploadId': uploadId,
        'uploadedParts': uploadedParts,
        'tags': tags,
        'description': description,
      };

  /// Metadata-only JSON for server sync.
  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'name': name,
        'title': title,
        'type': type.name,
        'localPath': localPath,
        'textContent': textContent,
        'sourceUri': sourceUri,
        'receivedAt': receivedAt.toIso8601String(),
        'mimeType': mimeType,
        'fileSize': fileSize,
        's3Key': s3Key,
        'tags': tags,
        'description': description,
      };

  factory SharedFile.fromJson(Map<String, dynamic> json) => SharedFile(
        id: json['id'] as String,
        name: json['name'] as String,
        title: json['title'] as String?,
        type: SharedFileType.values.byName(json['type'] as String),
        localPath: json['localPath'] as String?,
        textContent: json['textContent'] as String?,
        sourceUri: json['sourceUri'] as String?,
        receivedAt: DateTime.parse(json['receivedAt'] as String),
        mimeType: json['mimeType'] as String?,
        fileSize: json['fileSize'] as int? ?? 0,
        s3Key: json['s3Key'] as String?,
        uploadProgress: (json['uploadProgress'] as num?)?.toDouble(),
        uploadError: json['uploadError'] as String?,
        uploadId: json['uploadId'] as String?,
        uploadedParts: json['uploadedParts'] as String?,
        tags: (json['tags'] as List?)?.cast<String>() ?? [],
        description: json['description'] as String?,
        thumbS3Key: json['thumbS3Key'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SharedFile && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
