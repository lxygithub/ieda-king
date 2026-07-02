import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/shared_file.dart';
import '../providers/timeline_provider.dart';
import '../services/storage_service.dart';
import '../widgets/day_group.dart';
import '../widgets/draggable_fab.dart';
import '../widgets/file_card_grid.dart';
import 'detail_screen.dart';
import 'settings_screen.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  bool _isGridView = false;
  bool _showSearch = false;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadViewPref();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TimelineProvider>().loadFromDisk();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadViewPref() async {
    final storage = StorageService.instance;
    if (mounted) {
      setState(() => _isGridView = storage.decodeBool('grid_view') ?? false);
    }
  }

  Future<void> _toggleView() async {
    final newVal = !_isGridView;
    setState(() => _isGridView = newVal);
    final storage = StorageService.instance;
    storage.encodeBool('grid_view', newVal);
  }

  void _openDetail(SharedFile file) {
    if (_selectedIds.isNotEmpty) {
      _toggleSelection(file.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailScreen(file: file)),
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).batchDelete),
        content: Text(AppLocalizations.of(context).batchDeleteConfirm(count)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context).cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final provider = context.read<TimelineProvider>();
      for (final id in _selectedIds.toList()) {
        final files = provider.files.where((f) => f.id == id);
        for (final f in files) {
          await provider.deleteFile(f);
        }
      }
      _clearSelection();
    }
  }

  void _showBatchTagEditor() {
    if (_selectedIds.isEmpty) return;
    final provider = context.read<TimelineProvider>();
    // Collect union of all tags from selected files
    final existingTags = <String>{};
    for (final id in _selectedIds) {
      final file = provider.files.firstWhere((f) => f.id == id, orElse: () => provider.files.first);
      existingTags.addAll(file.tags);
    }
    final newTags = <String>{};
    final ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final l10n = AppLocalizations.of(context);
          final theme = Theme.of(context);
          final totalCount = _selectedIds.length;
          return AlertDialog(
            title: Text(l10n.batchAddTag),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info text
                  Text(l10n.batchAddTagConfirm(totalCount, newTags.length),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  // Tag input
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: l10n.batchAddTagHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (val) {
                      final tag = val.trim();
                      if (tag.isNotEmpty && !existingTags.contains(tag) && !newTags.contains(tag)) {
                        setDialogState(() => newTags.add(tag));
                      }
                      ctrl.clear();
                    },
                  ),
                  // New tags to add
                  if (newTags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(l10n.add, style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: newTags.map((t) => Chip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        backgroundColor: theme.colorScheme.primaryContainer,
                        onDeleted: () => setDialogState(() => newTags.remove(t)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      )).toList(),
                    ),
                  ],
                  // Existing tags (read-only, for reference)
                  if (existingTags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(l10n.tagLabel, style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: existingTags.map((t) => Chip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: newTags.isEmpty ? null : () async {
                  Navigator.pop(ctx, newTags.toList());
                },
                child: Text(l10n.done),
              ),
            ],
          );
        },
      ),
    ).then((result) {
      if (result != null && result is List<String> && result.isNotEmpty && mounted) {
        final provider = context.read<TimelineProvider>();
        provider.batchAddTags(_selectedIds.toList(), result);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).batchAddTagSuccess)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _showSearch ? _buildSearchField() : const Text(""),
        centerTitle: !_showSearch,
        leading: Consumer<TimelineProvider>(
          builder: (_, provider, __) {
            return IconButton(
              icon: Icon(_showSearch ? Icons.close : Icons.search),
              tooltip: _showSearch ? AppLocalizations.of(context).close : AppLocalizations.of(context).search,
              onPressed: () => _toggleSearch(provider),
            );
          },
        ),
        actions: [
          Consumer<TimelineProvider>(
            builder: (_, provider, __) {
              if (_showSearch) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (provider.files.isNotEmpty)
                    IconButton(
                      icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                      tooltip: _isGridView ? AppLocalizations.of(context).listView : AppLocalizations.of(context).gridView,
                      onPressed: _toggleView,
                    ),
                  Consumer<TimelineProvider>(
                    builder: (_, p, __) => IconButton(
                      icon: Icon(Icons.date_range,
                          color: p.hasDateFilter ? Theme.of(context).colorScheme.primary : null),
                      tooltip: p.hasDateFilter ? '清除日期筛选' : '日期筛选',
                      onPressed: () => _pickDateRange(context, p),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: '设置',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final p = context.read<TimelineProvider>();
          await p.fetchFromApi();
          p.retryAllFailed();
        },
        child: Consumer<TimelineProvider>(
        builder: (_, provider, __) {
          return Stack(
            children: [
              if (!provider.initialized && provider.loading)
                const Center(child: CircularProgressIndicator())
              else if (provider.loading)
                const Positioned(top: 0, left: 0, right: 0,
                  child: LinearProgressIndicator())
              else if (provider.files.isEmpty)
                _buildEmptyState(theme)
              else
                Column(
                  children: [
                    if (provider.isSearching || provider.hasTypeFilter)
                      _buildSearchBar(theme, provider),
                    _buildTypeFilter(theme, provider),
                    _buildDateFilterBanner(theme, provider),
                    _buildFailedBanner(theme, provider),
                    Expanded(
                      child: _isGridView
                          ? _buildGridTimeline(provider, provider.searchQuery)
                          : _buildListTimeline(provider, provider.searchQuery),
                    ),
                  ],
                ),
              const DraggableFab(),
            ],
          );
        },
      ),
        ),
      bottomNavigationBar: _selectedIds.isNotEmpty
          ? _buildSelectionBar()
          : null,
    );
  }

  Widget _buildSelectionBar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text(AppLocalizations.of(context).selected(_selectedIds.length),
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: AppLocalizations.of(context).cancel,
              onPressed: _clearSelection,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.label_outline, size: 20),
              tooltip: AppLocalizations.of(context).batchAddTag,
              onPressed: _showBatchTagEditor,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
              tooltip: AppLocalizations.of(context).delete,
              onPressed: _deleteSelected,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  // ===== Search =====

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      focusNode: _searchFocus,
      autofocus: true,
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).searchPlaceholder,
        border: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: (val) => context.read<TimelineProvider>().setSearchQuery(val),
    );
  }

  Widget _buildSearchBar(ThemeData theme, TimelineProvider provider) {
    final count = provider.filteredFiles.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          if (provider.isSearching) ...[
            Text(AppLocalizations.of(context).searchLabel(provider.searchQuery),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer)),
          ] else if (provider.hasTypeFilter) ...[
            Text(AppLocalizations.of(context).typeFilter,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer)),
          ],
          const Spacer(),
          Text(AppLocalizations.of(context).searchResult(count),
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.clear, size: 16),
            onPressed: () {
              _searchCtrl.clear();
              provider.clearSearch();
              provider.clearTypeFilter();
              _searchFocus.unfocus();
            },
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ===== Type filter =====

  Widget _buildDateFilterBanner(ThemeData theme, TimelineProvider provider) {
    if (!provider.hasDateFilter) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.date_range, size: 14, color: Colors.blue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${provider.startDate!.toIso8601String().substring(0, 10)} ~ ${provider.endDate!.toIso8601String().substring(0, 10)}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.blue),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.clear, size: 14),
            label: const Text('清除筛选', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => provider.clearDateFilter(),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedBanner(ThemeData theme, TimelineProvider provider) {
    final failed = provider.files.where((f) => f.s3Key == null && f.uploadError != null).length;
    if (failed == 0) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 14, color: Colors.orange),
          const SizedBox(width: 6),
          Text('$failed 个文件上传失败',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange)),
          const Spacer(),
          TextButton(
            onPressed: () => context.read<TimelineProvider>().retryAllFailed(),
            child: const Text('重试全部', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilter(ThemeData theme, TimelineProvider provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: SharedFileType.values.map((type) {
            final selected = provider.typeFilter.contains(type);
            final activeCount = provider.typeFilter.length;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(AppLocalizations.of(context).translateType(type), style: const TextStyle(fontSize: 12)),
                selected: selected,
                avatar: Icon(type.icon, size: 14),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) {
                  if (selected && activeCount == 1) {
                    provider.clearTypeFilter();
                  } else {
                    provider.toggleTypeFilter(type);
                  }
                },
              ),
            );
          }).toList()
            ..insert(0, Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                label: Text(AppLocalizations.of(context).allTypes, style: const TextStyle(fontSize: 12)),
                avatar: const Icon(Icons.all_inclusive, size: 14),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () => provider.clearTypeFilter(),
              ),
            )),
        ),
      ),
    );
  }

  void _toggleSearch(TimelineProvider provider) {
    if (_showSearch) {
      _searchCtrl.clear();
      provider.clearSearch();
      _searchFocus.unfocus();
    } else {
      _searchFocus.requestFocus();
    }
    setState(() => _showSearch = !_showSearch);
  }

  Future<void> _pickDateRange(BuildContext context, TimelineProvider provider) async {
    final now = DateTime.now();
    final initial = provider.hasDateFilter
        ? DateTimeRange(start: provider.startDate!, end: provider.endDate!)
        : DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: initial,
      confirmText: '确定',
      saveText: '确定',
    );
    if (picked != null) {
      await provider.setDateRange(picked.start, picked.end);
    }
  }

  // ===== Empty =====

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.share_outlined, size: 72,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('还没有收到任何分享',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('从其他应用分享文件、图片或文字到此应用',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.7))),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('点击重试'),
            onPressed: () {
              context.read<TimelineProvider>().fetchFromApi();
            },
          ),
        ],
      ),
    );
  }

  // ===== List view =====

  Widget _buildListTimeline(TimelineProvider provider, [String query = '']) {
    final grouped = provider.groupedByDay;
    final dates = grouped.keys.toList();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 200) {
            context.read<TimelineProvider>().loadMore();
          }
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: dates.length + (provider.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == dates.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
            );
          }
          final date = dates[index];
          final files = grouped[date]!;
          return DayGroup(
            dateStr: date,
            files: files,
            onTap: _openDetail,
            onDeleteAll: () => _confirmDeleteDay(date, files),
            query: query,
            selectedIds: _selectedIds,
            onToggleSelection: _toggleSelection,
            onRetry: (id) => context.read<TimelineProvider>().retryUpload(id),
          );
        },
      ),
    );
  }

  // ===== Grid view =====

  Widget _buildGridTimeline(TimelineProvider provider, [String query = '']) {
    final grouped = provider.groupedByDay;
    final dates = grouped.keys.toList();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 200) {
            context.read<TimelineProvider>().loadMore();
          }
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: dates.length + (provider.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == dates.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
            );
          }
          final date = dates[index];
          final files = grouped[date]!;
          return _buildGridDayGroup(date, files, query);
        },
      ),
    );
  }

  Widget _buildGridDayGroup(String dateStr, List<SharedFile> files, [String query = '']) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    final l10n = AppLocalizations.of(context);
    final weekdays = l10n.weekdays;

    String label;
    if (diff == 0) {
      label = l10n.today;
    } else if (diff == 1) {
      label = l10n.yesterday;
    } else {
      label = l10n.formatDate(date);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Day header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(width: 6),
              Text(weekdays[date.weekday - 1],
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8)),
                child: Text('${files.length}',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        // All files in one grid
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.75,
            ),
            itemCount: files.length,
            itemBuilder: (_, i) => FileCardGrid(
              file: files[i],
              onTap: () => _openDetail(files[i]),
              query: query,
              isSelected: _selectedIds.contains(files[i].id),
              onLongPress: () => _toggleSelection(files[i].id),
            ),
            ),
          ),
        ),
      ],
    );
  }

  // ===== Delete =====

  Future<void> _confirmDeleteDay(String date, List<SharedFile> files) async {
    final dateFmt = DateFormat('M月d日').format(DateTime.parse(date));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).deleteDayTitle),
        content: Text(AppLocalizations.of(context).deleteDayConfirm(dateFmt, files.length)),
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
      final provider = context.read<TimelineProvider>();
      for (final f in files) {
        await provider.deleteFile(f);
      }
    }
  }
}

