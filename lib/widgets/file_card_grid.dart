import 'dart:io';

import 'package:flutter/material.dart';

import '../models/shared_file.dart';
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
    if (file.type == SharedFileType.image && file.localPath != null) {
      return LayoutBuilder(
        builder: (_, constraints) => Image.file(
          File(file.localPath!),
          fit: BoxFit.cover,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          errorBuilder: (_, __, ___) => _fallbackIcon(theme),
        ),
      );
    }
    return _fallbackIcon(theme);
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
      case SharedFileType.document: return Colors.orange;
      case SharedFileType.url: return Colors.indigo;
      case SharedFileType.video: return Colors.purple;
      case SharedFileType.audio: return Colors.teal;
      case SharedFileType.apk: return Colors.amber;
      case SharedFileType.other: return theme.colorScheme.onSurfaceVariant;
    }
  }
}
