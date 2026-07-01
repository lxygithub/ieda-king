import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/shared_file.dart';
import '../services/api_service.dart';
import '../utils/file_handler.dart';
import 'highlighted_text.dart';

class FileCard extends StatelessWidget {
  final SharedFile file;
  final VoidCallback onTap;
  final String query;
  final bool showTime;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onRetry;

  const FileCard({
    super.key,
    required this.file,
    required this.onTap,
    this.query = '',
    this.showTime = true,
    this.isSelected = false,
    this.onLongPress,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr = DateFormat('HH:mm').format(file.receivedAt);
    final selMode = onLongPress != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Stack(
        children: [
          InkWell(
            onTap: selMode && isSelected ? null : onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showTime) ...[
                  SizedBox(
                    width: 48,
                    child: Text(timeStr,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 10, height: 10,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _dotColor(theme),
                      border: Border.all(
                          color: theme.colorScheme.outlineVariant, width: 2),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                          color: theme.colorScheme.outlineVariant, width: 0.5),
                    ),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                      child: Row(
                        children: [
                          _buildThumbnail(theme),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                HighlightedText(
                                  text: (file.title != null && file.title!.isNotEmpty) ? file.title! : file.name,
                                  query: query,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500),
                                ),
                                if (file.textContent != null && file.textContent!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2, bottom: 2),
                                    child: Text(
                                      file.textContent!.length > 200
                                          ? '${file.textContent!.substring(0, 200).replaceAll('\n', ' ')}...'
                                          : file.textContent!.replaceAll('\n', ' '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                          fontSize: 11),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    _typeChip(theme),
                                    if (file.fileSize > 0) ...[
                                      const SizedBox(width: 6),
                                      Text(FileHandler.formatSize(file.fileSize),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant,
                                              fontSize: 11)),
                                    ],
                                    if (file.uploadProgress != null)
                                      _uploadProgress(theme)
                                    else if (file.uploadError != null)
                                      _uploadError(theme)
                                    else if (file.s3Key != null)
                                      _uploadDone(theme)
                                    else if (file.localPath != null)
                                      _uploadPending(theme),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Positioned(
              left: 0, top: 0, bottom: 0, right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Icon(Icons.check_circle,
                        color: theme.colorScheme.primary, size: 22),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(ThemeData theme) {
    // Local file (fast, no network)
    if (file.localPath != null) {
      final localFile = File(file.localPath!);
      if (localFile.existsSync()) {
        if (file.type == SharedFileType.image) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48, height: 48,
              child: Image.file(
                localFile,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildS3Thumb(theme),
              ),
            ),
          );
        }
        // Non-image local files (e.g. video) fall through to S3 thumb
      }
    }
    // S3 thumbnail (image no localPath, or video)
    return _buildS3Thumb(theme);
  }

  Widget _buildS3Thumb(ThemeData theme) {
    if (file.thumbS3Key == null) {
      if (file.type == SharedFileType.video) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48, height: 48,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _fallbackIcon(theme),
                Center(child: Container(
                  width: 28, height: 28,
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                )),
              ],
            ),
          ),
        );
      }
      return _fallbackIcon(theme);
    }
    final url = '${ApiService.instance.baseUrl}${file.thumbUrl}?token=${ApiService.instance.token ?? ''}';
    final thumb = CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => _fallbackIcon(theme),
      errorWidget: (_, __, ___) => _fallbackIcon(theme),
    );
    if (file.type == SharedFileType.video) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48, height: 48,
          child: Stack(
            fit: StackFit.expand,
            children: [
              thumb,
              Center(child: Container(
                width: 28, height: 28,
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
              )),
            ],
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48, height: 48,
        child: thumb,
      ),
    );
  }

  Widget _fallbackIcon(ThemeData theme) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(file.type.icon, color: _typeColor(theme), size: 24),
    );
  }

  Widget _typeChip(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _typeColor(theme).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(file.type.label,
          style: theme.textTheme.labelSmall?.copyWith(
              color: _typeColor(theme), fontSize: 10)),
    );
  }

  Widget _uploadProgress(ThemeData theme) {
    final pct = (file.uploadProgress! * 100).toInt().clamp(0, 100);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: SizedBox(
        width: 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: file.uploadProgress,
                minHeight: 4,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            Text('$pct%',
                style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 8, color: theme.colorScheme.primary)),
          ],
        ),
      ),
    );
  }

  Widget _uploadError(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        onTap: onRetry,
        child: Tooltip(
          message: file.uploadError ?? '上传失败',
          child: const Icon(Icons.cloud_off, size: 14, color: Colors.orange),
        ),
      ),
    );
  }

  Widget _uploadPending(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        onTap: onRetry,
        child: const Tooltip(
          message: '等待上传',
          child: Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _uploadDone(ThemeData theme) {
    return const Padding(
      padding: EdgeInsets.only(left: 6),
      child: Icon(Icons.cloud_done, size: 14, color: Colors.green),
    );
  }

  Color _dotColor(ThemeData theme) =>
      theme.colorScheme.primary.withValues(alpha: 0.3);

  Color _typeColor(ThemeData theme) {
    switch (file.type) {
      case SharedFileType.image: return Colors.green;
      case SharedFileType.text: return Colors.blue;
      case SharedFileType.markdown: return Colors.teal;
      case SharedFileType.document: return Colors.orange;
      case SharedFileType.url: return Colors.indigo;
      case SharedFileType.video: return Colors.purple;
      case SharedFileType.audio: return Colors.teal;
      case SharedFileType.apk: return Colors.amber;
      case SharedFileType.other: return theme.colorScheme.onSurfaceVariant;
    }
  }
}
