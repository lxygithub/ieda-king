import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/shared_file.dart';
import '../providers/timeline_provider.dart';

class TextEditScreen extends StatefulWidget {
  final SharedFile file;

  const TextEditScreen({super.key, required this.file});

  @override
  State<TextEditScreen> createState() => _TextEditScreenState();
}

class _TextEditScreenState extends State<TextEditScreen> {
  late TextEditingController _ctrl;
  bool _isSaving = false;
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.file.textContent ?? '');
    _charCount = _ctrl.text.length;
    _ctrl.addListener(_updateCharCount);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_updateCharCount);
    _ctrl.dispose();
    super.dispose();
  }

  void _updateCharCount() {
    if (mounted) {
      setState(() {
        _charCount = _ctrl.text.length;
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await context
          .read<TimelineProvider>()
          .updateTextContent(widget.file.id, _ctrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存成功'),
            duration: Duration(seconds: 1),
          ),
        );
        Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.title ?? widget.file.name),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                '$_charCount 字',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _ctrl,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(12),
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
      ),
    );
  }
}
