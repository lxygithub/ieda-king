import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/shared_file.dart';
import '../providers/timeline_provider.dart';

class MarkdownViewScreen extends StatefulWidget {
  final SharedFile file;

  const MarkdownViewScreen({super.key, required this.file});

  @override
  State<MarkdownViewScreen> createState() => _MarkdownViewScreenState();
}

class _MarkdownViewScreenState extends State<MarkdownViewScreen> {
  bool _isEditing = false;
  late TextEditingController _editCtrl;
  bool _isSaving = false;
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: widget.file.textContent ?? '');
    _charCount = _editCtrl.text.length;
    _editCtrl.addListener(_updateCharCount);
  }

  @override
  void dispose() {
    _editCtrl.removeListener(_updateCharCount);
    _editCtrl.dispose();
    super.dispose();
  }

  void _updateCharCount() {
    if (mounted) {
      setState(() {
        _charCount = _editCtrl.text.length;
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await context
          .read<TimelineProvider>()
          .updateTextContent(widget.file.id, _editCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存成功'),
            duration: Duration(seconds: 1),
          ),
        );
        setState(() {
          _isEditing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _copyContent() {
    final content = _isEditing ? _editCtrl.text : (widget.file.textContent ?? '');
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _shareContent() {
    final content = _isEditing ? _editCtrl.text : (widget.file.textContent ?? '');
    Share.share(content, subject: widget.file.title ?? widget.file.name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = widget.file.textContent ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.title ?? widget.file.name),
        actions: [
          if (_isEditing) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  '$_charCount 字',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              tooltip: AppLocalizations.of(context).save,
              onPressed: _isSaving ? null : _save,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.content_copy),
              tooltip: '复制',
              onPressed: _copyContent,
            ),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: AppLocalizations.of(context).share,
              onPressed: _shareContent,
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: '编辑',
              onPressed: () => setState(() => _isEditing = true),
            ),
          ],
        ],
      ),
      body: _isEditing ? _buildEditor(theme) : _buildViewer(theme, content),
    );
  }

  Widget _buildEditor(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _editCtrl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.all(12),
          hintText: '输入 Markdown 内容...',
        ),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      ),
    );
  }

  Widget _buildViewer(ThemeData theme, String content) {
    if (content.isEmpty) {
      return const Center(
        child: Text('无内容'),
      );
    }

    return Markdown(
      data: content,
      selectable: true,
      padding: const EdgeInsets.all(16),
      styleSheet: MarkdownStyleSheet(
        h1: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
        h2: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        h3: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        code: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          fontSize: 13,
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquote: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 4),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
        a: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        listBullet: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        tableHead: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        tableBody: theme.textTheme.bodyMedium,
        tableBorder: TableBorder.all(color: theme.colorScheme.outlineVariant, width: 1),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
