import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/shared_file.dart';
import '../providers/timeline_provider.dart';
import '../widgets/day_group.dart';
import '../widgets/draggable_fab.dart';
import '../widgets/file_card_grid.dart';
import 'detail_screen.dart';

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
  final Set<String> _collapsedGridMinutes = {};
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
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _isGridView = prefs.getBool('grid_view') ?? false);
    }
  }

  Future<void> _toggleView() async {
    final newVal = !_isGridView;
    setState(() => _isGridView = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('grid_view', newVal);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _showSearch ? _buildSearchField() : Text(AppLocalizations.of(context).timeline),
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
              if (provider.files.isEmpty || _showSearch) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                tooltip: _isGridView ? AppLocalizations.of(context).listView : AppLocalizations.of(context).gridView,
                onPressed: _toggleView,
              );
            },
          ),
        ],
      ),
      body: Consumer<TimelineProvider>(
        builder: (_, provider, __) {
          return Stack(
            children: [
              if (!provider.initialized && provider.loading)
                const Center(child: CircularProgressIndicator())
              else if (provider.files.isEmpty)
                _buildEmptyState(theme)
              else
                Column(
                  children: [
                    if (provider.isSearching || provider.hasTypeFilter)
                      _buildSearchBar(theme, provider),
                    _buildTypeFilter(theme, provider),
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
      bottomNavigationBar: _selectedIds.isNotEmpty
          ? _buildSelectionBar()
          : null,
    );
  }

  Widget _buildSelectionBar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Text(AppLocalizations.of(context).selected(_selectedIds.length),
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface)),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.clear, size: 18),
            label: Text(AppLocalizations.of(context).cancel),
            onPressed: _clearSelection,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(AppLocalizations.of(context).delete),
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
            onPressed: _deleteSelected,
          ),
        ],
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
        ],
      ),
    );
  }

  // ===== List view =====

  Widget _buildListTimeline(TimelineProvider provider, [String query = '']) {
    final grouped = provider.groupedByDay;
    final dates = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: dates.length,
      itemBuilder: (context, index) {
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
    );
  }

  // ===== Grid view =====

  Widget _buildGridTimeline(TimelineProvider provider, [String query = '']) {
    final grouped = provider.groupedByDay;
    final dates = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: dates.length,
      itemBuilder: (context, index) {
        final date = dates[index];
        final files = grouped[date]!;
        return _buildGridDayGroup(date, files, query);
      },
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
    } else if (diff == 2) {
      label = l10n.dayBefore;
    } else if (diff < 7) {
      label = l10n.daysAgo(diff);
    } else {
      label = l10n.formatDate(date);
    }

    // Group by minute
    final minuteMap = <String, List<SharedFile>>{};
    for (final f in files) {
      final key = f.receivedAt.toIso8601String().substring(0, 16);
      minuteMap.putIfAbsent(key, () => []).add(f);
    }
    final minuteKeys = minuteMap.keys.toList()..sort((a, b) => b.compareTo(a));

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
        // Minute groups
        ...minuteKeys.map((minuteKey) {
          final grpFiles = minuteMap[minuteKey]!;
          final collapsed = _collapsedGridMinutes.contains(minuteKey);
          final expanded = !collapsed;
          return _buildGridMinuteGroup(minuteKey, grpFiles, expanded, query);
        }),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildGridMinuteGroup(String minuteKey, List<SharedFile> files,
      bool expanded, String query) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final timeStr = DateFormat('HH:mm').format(files.first.receivedAt);

    if (files.length == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 0.75,
          ),
          itemCount: 1,
          itemBuilder: (_, i) => FileCardGrid(
            file: files.first, onTap: () => _openDetail(files.first),
            query: query,
            isSelected: _selectedIds.contains(files.first.id),
            onLongPress: () => _toggleSelection(files.first.id),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Timestamp header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Text(timeStr,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 6),
              Text(l10n.items(files.length),
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() {
                  if (expanded) {
                    _collapsedGridMinutes.add(minuteKey);
                  } else {
                    _collapsedGridMinutes.remove(minuteKey);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: expanded
                        ? theme.colorScheme.surfaceContainerHighest
                        : theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        expanded ? Icons.unfold_less : Icons.unfold_more,
                        size: 14,
                        color: expanded
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onPrimary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        expanded ? l10n.collapse : l10n.expandAll,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          color: expanded
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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

