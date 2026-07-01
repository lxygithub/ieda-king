import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/shared_file.dart';
import '../services/api_service.dart';
import '../utils/file_handler.dart';
import 'highlighted_text.dart';

class FileCardGrid extends StatelessWidget {
  final SharedFile file;
  final VoidCallback onTap;
  final String query;
  final bool isSelected;
  final VoidCallback? onLongPress;

  const FileCardGrid({
    super.key,
    required this.file,
    required this.onTap,
    this.query = '',
    this.isSelected = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selColor = theme.colorScheme.primary;

    return Stack(
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          color: isSelected
              ? selColor.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? selColor : theme.colorScheme.outlineVariant,
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: InkWell(
            onTap: isSelected ? null : onTap,
            onLongPress: onLongPress,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildThumbnail(theme)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HighlightedText(
                        text: file.name,
                        query: query,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      if (file.fileSize > 0)
                        Text(
                          FileHandler.formatSize(file.fileSize),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isSelected)
          Positioned(
            top: 6, right: 6,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 14, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _buildThumbnail(ThemeData theme) {
    // Local file (fast, no network)
    if (file.localPath != null) {
      final localFile = File(file.localPath!);
      if (localFile.existsSync()) {
        if (file.type == SharedFileType.image) {
          return LayoutBuilder(
            builder: (_, constraints) => Image.file(
              localFile,
              fit: BoxFit.cover,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              errorBuilder: (_, __, ___) => _buildS3Thumb(theme),
            ),
          );
        }
        // For non-image local files, still show S3 thumb (videos show play overlay)
      }
    }
    // Thumbnail from S3 (fallback for missing localPath, or direct for video)
    if (file.type == SharedFileType.image || file.type == SharedFileType.video) {
      return _buildS3Thumb(theme);
    }
    return _fallbackIcon(theme);
  }

  Widget _buildS3Thumb(ThemeData theme) {
    if (file.thumbS3Key == null) {
      // Show play icon overlay for videos even without thumbnail
      if (file.type == SharedFileType.video) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _fallbackIcon(theme),
            Center(
              child: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
              ),
            ),
          ],
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
      return Stack(
        fit: StackFit.expand,
        children: [
          thumb,
          Center(
            child: Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
            ),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (_, constraints) => SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: thumb,
      ),
    );
  }

  Widget _fallbackIcon(ThemeData theme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Center(
        child: Icon(file.type.icon, size: 36,
            color: _typeColor(theme).withValues(alpha: 0.6)),
      ),
    );
  }


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
