import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../models/shared_file.dart';
import '../providers/timeline_provider.dart';
import '../services/api_service.dart';
import '../utils/file_handler.dart';
import 'text_edit_screen.dart';

class DetailScreen extends StatefulWidget {
  final SharedFile file;

  const DetailScreen({super.key, required this.file});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  String? _textPreview;
  bool _previewLoading = true;
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late FocusNode _titleFocus;
  late FocusNode _descFocus;
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.file.title ?? widget.file.name);
    _descCtrl = TextEditingController(text: widget.file.description ?? '');
    _titleFocus = FocusNode();
    _descFocus = FocusNode();
    _tags = List.from(widget.file.tags);
    _loadPreview();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _titleFocus.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    // First try to get from provider (latest edited content)
    final provider = context.read<TimelineProvider>();
    final files = provider.files;
    final idx = files.indexWhere((f) => f.id == widget.file.id);
    String? content;
    if (idx != -1 && files[idx].textContent != null) {
      content = files[idx].textContent;
    } else {
      // Fallback to file
      content = await FileHandler.readTextPreview(widget.file);
    }
    if (mounted) {
      setState(() {
        _textPreview = content;
        _previewLoading = false;
      });
    }
  }

  Future<void> _saveTitle() async {
    final title = _titleCtrl.text.trim();
    await context.read<TimelineProvider>().updateTitle(widget.file.id, title);
    _titleFocus.unfocus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标题已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _saveDescription() async {
    final desc = _descCtrl.text.trim();
    await context
        .read<TimelineProvider>()
        .updateDescription(widget.file.id, desc);
    _descFocus.unfocus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('描述已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _saveTags() async {
    await context.read<TimelineProvider>().updateTags(widget.file.id, _tags);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标签已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = widget.file;

    return Scaffold(
      appBar: AppBar(
        title: Text(f.title != null && f.title!.isNotEmpty ? f.title! : f.name,
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              icon: const Icon(Icons.share),
              tooltip: AppLocalizations.of(context).share,
              onPressed: () => _shareFile(f)),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: AppLocalizations.of(context).delete,
              onPressed: () => _confirmDelete(f)),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPreview(theme, f),
            _buildTitleSection(theme, f),
            _buildTagSection(theme, f),
            _buildDescriptionSection(theme, f),
            const Divider(),
            _buildOpenSection(theme, f),
            const Divider(),
            _buildMetadata(theme, f),
          ],
        ),
      ),
    );
  }

  // ======== Preview ========

  Widget _buildPreview(ThemeData theme, SharedFile f) {
    switch (f.type) {
      case SharedFileType.image:
        return _buildImagePreview(f);
      case SharedFileType.video:
        return _buildVideoCover(f);
      case SharedFileType.text:
        return _buildTextPreview(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildImagePreview(SharedFile f) {
    // Local file
    if (f.localPath != null) {
      final file = File(f.localPath!);
      if (file.existsSync()) {
        return SizedBox(
          height: 360,
          child: GestureDetector(
            onTap: () => _showOpenSheet(f),
            child: PhotoView(
              imageProvider: FileImage(file),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              backgroundDecoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
              loadingBuilder: (_, __) => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              errorBuilder: (_, __, ___) => _noPreview(),
            ),
          ),
        );
      }
    }
    // S3 image (no local file)
    if (f.s3Key != null) {
      return _S3DetailImage(file: f);
    }
    return _noPreview();
  }

  Widget _buildVideoCover(SharedFile f) {
    Widget cover;
    if (f.thumbS3Key != null) {
      final token = ApiService.instance.token;
      final url =
          '${ApiService.instance.baseUrl}${f.thumbUrl}?token=${token ?? ''}';
      cover = CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => const SizedBox.shrink(),
          errorWidget: (_, __, ___) => const SizedBox.shrink());
    } else {
      cover = const SizedBox.shrink();
    }
    return Container(
      height: 300,
      width: double.infinity,
      color: Colors.black87,
      child: Stack(
        fit: StackFit.expand,
        children: [
          cover,
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_circle_outline,
                    size: 72, color: Colors.white54),
                const SizedBox(height: 16),
                Text(f.name,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 14)),
                if (f.fileSize > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(FileHandler.formatSize(f.fileSize),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12)),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('用系统播放器打开'),
                  onPressed: () => _openExternal(f),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextPreview(ThemeData theme) {
    if (_previewLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_textPreview == null) return _noPreview();

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TextEditScreen(file: widget.file),
          ),
        );
        // Refresh after returning from edit screen
        if (mounted) {
          setState(() {
            _previewLoading = true;
          });
          _loadPreview();
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.edit, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  '点击编辑',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_textPreview!.length} 字',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  _textPreview!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontFamily: 'monospace', height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======== Title ========

  Widget _buildTitleSection(ThemeData theme, SharedFile f) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('标题', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _titleCtrl,
            maxLines: 1,
            decoration: InputDecoration(
              hintText: '输入标题（可选）',
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check, size: 18),
                onPressed: _saveTitle,
              ),
            ),
            onSubmitted: (_) => _saveTitle(),
          ),
        ],
      ),
    );
  }

  // ======== Tags ========

  Widget _buildTagSection(ThemeData theme, SharedFile f) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(AppLocalizations.of(context).tagLabel,
                  style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 16),
                label: Text(AppLocalizations.of(context).manage),
                onPressed: () => _showTagEditor(f),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _tags.isEmpty
              ? Text(AppLocalizations.of(context).noTag,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
              : Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _tags
                      .map((t) => Chip(
                            label:
                                Text(t, style: const TextStyle(fontSize: 12)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () {
                              setState(() => _tags.remove(t));
                              _saveTags();
                            },
                          ))
                      .toList(),
                ),
        ],
      ),
    );
  }

  void _showTagEditor(SharedFile f) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).addTag),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).tagHint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (val) {
                final tag = val.trim();
                if (tag.isNotEmpty && !_tags.contains(tag)) {
                  setState(() => _tags.add(tag));
                  _saveTags();
                }
                ctrl.clear();
              },
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _tags
                    .map((t) => Chip(
                          label: Text(t, style: const TextStyle(fontSize: 12)),
                          onDeleted: () {
                            setState(() => _tags.remove(t));
                            _saveTags();
                          },
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (_tags.isNotEmpty) {
                _saveTags();
              }
              Navigator.pop(ctx);
            },
            child: Text(AppLocalizations.of(context).done),
          ),
        ],
      ),
    );
  }

  // ======== Description ========

  Widget _buildDescriptionSection(ThemeData theme, SharedFile f) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).descriptionLabel,
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).addDescription,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check, size: 18),
                onPressed: _saveDescription,
              ),
            ),
            onChanged: (_) => _saveDescription(),
          ),
        ],
      ),
    );
  }

  // ======== Open section ========

  Widget _buildOpenSection(ThemeData theme, SharedFile f) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).openWith,
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _actionChip(
                  icon: Icons.open_in_new,
                  label: '系统应用',
                  onTap: () => _openExternal(f)),
              _actionChip(
                  icon: Icons.share,
                  label: AppLocalizations.of(context).share,
                  onTap: () => _shareFile(f)),
              if (f.type == SharedFileType.text || f.textContent != null)
                _actionChip(
                    icon: Icons.content_copy,
                    label: '复制文本',
                    onTap: () => _copyText(f)),
              _actionChip(
                  icon: Icons.content_paste,
                  label: AppLocalizations.of(context).copyPath,
                  onTap: () => _copyPath(f)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(AppLocalizations.of(context).chooseApp),
              onPressed: () => _openExternal(f),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return ActionChip(
        avatar: Icon(icon, size: 18), label: Text(label), onPressed: onTap);
  }

  // ======== Actions ========

  void _showOpenSheet(SharedFile f) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(AppLocalizations.of(context).openWith,
                  style: Theme.of(ctx).textTheme.titleSmall),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(AppLocalizations.of(context).chooseApp),
              subtitle: Text(AppLocalizations.of(context).systemApp),
              onTap: () {
                Navigator.pop(ctx);
                _openExternal(f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('分享'),
              subtitle: const Text('通过系统分享发送'),
              onTap: () {
                Navigator.pop(ctx);
                _shareFile(f);
              },
            ),
            if (f.type == SharedFileType.text || f.textContent != null)
              ListTile(
                leading: const Icon(Icons.content_copy),
                title: const Text('复制内容'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyText(f);
                },
              ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('复制文件路径'),
              onTap: () {
                Navigator.pop(ctx);
                _copyPath(f);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternal(SharedFile f) async {
    if (f.localPath != null && File(f.localPath!).existsSync()) {
      final result = await OpenFilex.open(f.localPath!);
      if (result.type != ResultType.done && mounted) {
        _showSnack('打开失败: ${result.message}');
      }
    } else if (f.s3Key != null) {
      final uri = Uri.parse(
          '${ApiService.instance.baseUrl}${f.downloadUrl}?token=${ApiService.instance.token ?? ''}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showSnack('无法打开: $uri');
      }
    } else {
      _showSnack('无文件可打开');
    }
  }

  Future<void> _shareFile(SharedFile f) async {
    if (f.localPath != null && File(f.localPath!).existsSync()) {
      await Share.shareXFiles([XFile(f.localPath!)], text: f.name);
    } else if (f.localPath != null) {
      _showSnack('本地文件不存在');
    } else if (f.textContent != null) {
      await Share.share(f.textContent!, subject: f.name);
    } else {
      _showSnack('无可分享的内容');
    }
  }

  Future<void> _copyText(SharedFile f) async {
    final content = f.textContent ?? _textPreview;
    if (content == null || content.isEmpty) {
      _showSnack('无文本内容可复制');
      return;
    }
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) _showSnack('文本已复制到剪贴板');
  }

  Future<void> _copyPath(SharedFile f) async {
    if (f.localPath == null) {
      _showSnack('无文件路径');
      return;
    }
    await Clipboard.setData(ClipboardData(text: f.localPath!));
    if (mounted) _showSnack('路径已复制');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ======== Metadata ========

  Widget _buildMetadata(ThemeData theme, SharedFile f) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).detailInfo,
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          _metaRow(theme, AppLocalizations.of(context).fileName, f.name),
          _metaRow(theme, AppLocalizations.of(context).fileType, f.type.label),
          if (f.mimeType != null) _metaRow(theme, 'MIME', f.mimeType!),
          if (f.fileSize > 0)
            _metaRow(theme, AppLocalizations.of(context).fileSize,
                _formatSize(f.fileSize)),
          _metaRow(theme, AppLocalizations.of(context).receiveTime,
              DateFormat('yyyy-MM-dd HH:mm:ss').format(f.receivedAt)),
          if (f.localPath != null)
            _metaRow(
                theme, AppLocalizations.of(context).localPath, f.localPath!,
                maxLines: 2),
          if (f.sourceUri != null)
            _metaRow(theme, AppLocalizations.of(context).source, f.sourceUri!),
        ],
      ),
    );
  }

  Widget _metaRow(ThemeData theme, String label, String value,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: InkWell(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: value));
                _showSnack('已复制');
              },
              child: Text(value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noPreview() {
    return Container(
      height: 200,
      alignment: Alignment.center,
      child:
          Icon(Icons.broken_image_outlined, size: 48, color: Colors.grey[400]),
    );
  }

  Future<void> _confirmDelete(SharedFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).deleteRecord),
        content: Text(AppLocalizations.of(context).deleteConfirm(f.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(context).cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(AppLocalizations.of(context).delete)),
        ],
      ),
    );
    if (ok == true && mounted) {
      context.read<TimelineProvider>().deleteFile(f);
      Navigator.pop(context);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Loads S3 thumbnail via CachedNetworkImage, with action buttons.
class _S3DetailImage extends StatelessWidget {
  final SharedFile file;

  const _S3DetailImage({required this.file});

  @override
  Widget build(BuildContext context) {
    final token = ApiService.instance.token;
    if (token == null || token.isEmpty) return _noPreview();
    final thumbUrl =
        '${ApiService.instance.baseUrl}${file.thumbUrl}?token=$token';

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 360,
          child: Center(
            child: GestureDetector(
              child: CachedNetworkImage(
                imageUrl: thumbUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                errorWidget: (_, __, ___) => _noPreview(),
              ),
              onTap: () => {_openOriginal(context, file)},
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _actionBtn(context, Icons.open_in_new, '查看原图',
                () => _openOriginal(context, file)),
            const SizedBox(width: 16),
            _actionBtn(context, Icons.download, '保存到手机',
                () => _saveToGallery(context, file)),
          ],
        ),
      ],
    );
  }

  Widget _actionBtn(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Future<void> _openOriginal(BuildContext context, SharedFile f) async {
    final token = ApiService.instance.token ?? '';
    final url = '${ApiService.instance.baseUrl}${f.downloadUrl}?token=$token';
    if (f.localPath != null && File(f.localPath!).existsSync()) {
      await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _FullScreenImage(file: f, localPath: f.localPath!),
          ));
    } else if (f.s3Key != null) {
      await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _FullScreenImage(file: f, imageUrl: url),
          ));
    }
  }

  Future<void> _saveToGallery(BuildContext context, SharedFile f) async {
    _showSnack(context, '正在下载...');
    try {
      final token = ApiService.instance.token ?? '';
      final url = '${ApiService.instance.baseUrl}${f.downloadUrl}?token=$token';
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        _showSnack(context, '下载失败');
        return;
      }

      final dir = await getTemporaryDirectory();
      final tmpFile = File('${dir.path}/${f.name}');
      await tmpFile.writeAsBytes(resp.bodyBytes);

      final result = await OpenFilex.open(tmpFile.path);
      if (result.type != ResultType.done && context.mounted) {
        _showSnack(context, '保存失败: ${result.message}');
      } else if (context.mounted) {
        _showSnack(context, '已保存到临时目录');
      }
    } catch (e) {
      _showSnack(context, '保存失败: $e');
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _noPreview() {
    return Container(
      height: 200,
      alignment: Alignment.center,
      child:
          Icon(Icons.broken_image_outlined, size: 48, color: Colors.grey[400]),
    );
  }
}

/// Full-screen image viewer with zoom and save button.
class _FullScreenImage extends StatelessWidget {
  final SharedFile file;
  final String? localPath;
  final String? imageUrl;

  const _FullScreenImage({
    required this.file,
    this.localPath,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final ImageProvider provider;
    if (localPath != null) {
      provider = FileImage(File(localPath!));
    } else if (imageUrl != null) {
      provider = CachedNetworkImageProvider(imageUrl!);
    } else {
      provider = const AssetImage('');
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '保存到手机',
            onPressed: () => _save(context),
          ),
        ],
      ),
      body: Center(
        child: PhotoView(
          imageProvider: provider,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 4,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          loadingBuilder: (_, __) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image_outlined,
                size: 64, color: Colors.white38),
          ),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在下载...')),
    );
    try {
      final token = ApiService.instance.token ?? '';
      final url =
          '${ApiService.instance.baseUrl}${file.downloadUrl}?token=$token';
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('下载失败')),
          );
        return;
      }

      final dir = await getTemporaryDirectory();
      final tmpFile = File('${dir.path}/${file.name}');
      await tmpFile.writeAsBytes(resp.bodyBytes);

      final result = await OpenFilex.open(tmpFile.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
            result.type == ResultType.done
                ? '已保存到临时目录'
                : '保存失败: ${result.message}',
          )),
        );
      }
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
    }
  }
}
