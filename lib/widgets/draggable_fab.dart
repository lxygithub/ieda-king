import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/timeline_provider.dart';

class DraggableFab extends StatefulWidget {
  const DraggableFab({super.key});

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab> {
  // Drag state
  bool _initialized = false;
  Offset _position = Offset.zero;
  double _screenWidth = 0;
  double _screenHeight = 0;
  bool _hidden = false;
  final double _fabSize = 52;
  final double _edgeMargin = 36;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final size = MediaQuery.of(context).size;
    _screenWidth = size.width;
    _screenHeight = size.height;
    if (_screenWidth > 0) {
      _position = Offset(_screenWidth - _fabSize - _edgeMargin, _screenHeight * 0.7);
      _initialized = true;
      setState(() {});
    }
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _position += d.delta;
      _position = Offset(
        _position.dx.clamp(-_fabSize * 0.5, _screenWidth - _fabSize * 0.5),
        _position.dy.clamp(80, _screenHeight - _fabSize - 80),
      );
    });
  }

  void _onDragEnd(DragEndDetails d) {
    setState(() {
      // Snap to nearest edge
      final leftDist = _position.dx;
      final rightDist = _screenWidth - _position.dx - _fabSize;
      if (leftDist < rightDist) {
        _position = Offset(-_fabSize * 0.4, _position.dy); // snap left-hidden
        _hidden = true;
      } else {
        _position = Offset(_screenWidth - _fabSize * 0.6, _position.dy); // snap right-hidden
        _hidden = true;
      }
    });
  }

  void _onTap() {
    if (_hidden) {
      setState(() {
        // Pull out to full visibility
        if (_position.dx < _screenWidth / 2) {
          _position = Offset(_edgeMargin, _position.dy);
        } else {
          _position = Offset(_screenWidth - _fabSize - _edgeMargin, _position.dy);
        }
        _hidden = false;
      });
      return;
    }
    _showActionSheet();
  }

  void _showActionSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l10n.addContent, style: Theme.of(ctx).textTheme.titleSmall),
            ),
            ListTile(
              leading: const Icon(Icons.file_open),
              title: Text(l10n.pickFile),
              subtitle: Text(l10n.pickFileSub),
              onTap: () { Navigator.pop(ctx); _pickFile(); },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text(l10n.inputText),
              subtitle: Text(l10n.inputTextSub),
              onTap: () { Navigator.pop(ctx); _showTextInput(); },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: Text(l10n.importClipboard),
              subtitle: Text(l10n.importClipboardSub),
              onTap: () { Navigator.pop(ctx); _importClipboard(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null || !mounted) return;
    final paths = result.paths.whereType<String>().toList();
    if (paths.isEmpty) return;
    await context.read<TimelineProvider>().ingestMultipleFiles(paths);
  }

  Future<void> _showTextInput() async {
    String? clipboard;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      clipboard = data?.text;
    } catch (_) {}
    if (!mounted) return;

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _TextInputPage(initialText: clipboard ?? ''),
      ),
    );
    if (result != null && result.trim().isNotEmpty && mounted) {
      await context.read<TimelineProvider>().ingestText(result.trim());
    }
  }

  Future<void> _importClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null || data!.text!.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).clipboardEmpty)),
          );
        }
        return;
      }
      if (!mounted) return;
      await context.read<TimelineProvider>().ingestText(data.text!.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).imported)),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox.shrink();
    final theme = Theme.of(context);
    // Show tab when hidden
    if (_hidden) {
      final isLeft = _position.dx < _screenWidth / 2;
      return Positioned(
        left: isLeft ? 0 : null,
        right: isLeft ? null : 0,
        top: _position.dy,
        child: GestureDetector(
          onTap: _onTap,
          onPanUpdate: _onDragUpdate,
          onPanEnd: _onDragEnd,
          child: Container(
            width: 12,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(isLeft ? 0 : 6),
                right: Radius.circular(isLeft ? 6 : 0),
              ),
            ),
            child: Center(
              child: Icon(Icons.chevron_left, size: 12,
                  color: theme.colorScheme.onPrimary),
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onTap: _onTap,
        onPanUpdate: _onDragUpdate,
        onPanEnd: _onDragEnd,
        child: Container(
          width: _fabSize,
          height: _fabSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Icon(Icons.add, color: theme.colorScheme.onPrimary, size: 28),
          ),
        ),
      ),
    );
  }
}

class _TextInputPage extends StatefulWidget {
  final String initialText;
  const _TextInputPage({required this.initialText});

  @override
  State<_TextInputPage> createState() => _TextInputPageState();
}

class _TextInputPageState extends State<_TextInputPage> {
  late TextEditingController _ctrl;
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _charCount = widget.initialText.length;
    _ctrl.addListener(() {
      setState(() => _charCount = _ctrl.text.length);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).textInputTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(AppLocalizations.of(context).charCount(_charCount),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _charCount > 0
                  ? () => Navigator.pop(context, _ctrl.text)
                  : null,
              child: Text(AppLocalizations.of(context).add),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context).textHint,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
