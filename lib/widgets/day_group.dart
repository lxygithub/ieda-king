import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/shared_file.dart';
import 'file_card.dart';

class DayGroup extends StatefulWidget {
  final String dateStr;
  final List<SharedFile> files;
  final ValueChanged<SharedFile> onTap;
  final VoidCallback? onDeleteAll;
  final String query;
  final Set<String> selectedIds;
  final ValueChanged<String>? onToggleSelection;
  final ValueChanged<String>? onRetry;

  const DayGroup({
    super.key,
    required this.dateStr,
    required this.files,
    required this.onTap,
    this.onDeleteAll,
    this.query = '',
    this.selectedIds = const {},
    this.onToggleSelection,
    this.onRetry,
  });

  @override
  State<DayGroup> createState() => _DayGroupState();
}

class _DayGroupState extends State<DayGroup> {
  /// Track expanded groups by minute key. Default: all expanded.
  late Set<String> _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = _allMinuteKeys.toSet();
  }

  String get _displayDate {
    final date = DateTime.parse(widget.dateStr);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return AppLocalizations.of(context).today;
    if (diff == 1) return AppLocalizations.of(context).yesterday;
    if (diff == 2) return AppLocalizations.of(context).dayBefore;
    if (diff < 7) return AppLocalizations.of(context).daysAgo(diff);
    return AppLocalizations.of(context).formatDate(date);
  }

  String get _weekday {
    final date = DateTime.parse(widget.dateStr);
    return AppLocalizations.of(context).weekdays[date.weekday - 1];
  }

  /// All minute keys for this day
  List<String> get _allMinuteKeys {
    final keys = <String>{};
    for (final f in widget.files) {
      keys.add(f.receivedAt.toIso8601String().substring(0, 16));
    }
    return keys.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Minute-grouped files
  Map<String, List<SharedFile>> get _minuteGroups {
    final map = <String, List<SharedFile>>{};
    for (final f in widget.files) {
      final key = f.receivedAt.toIso8601String().substring(0, 16);
      map.putIfAbsent(key, () => []).add(f);
    }
    for (final list in map.values) {
      list.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _minuteGroups;
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Day header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                _displayDate,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _weekday,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.files.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              if (widget.onDeleteAll != null)
                IconButton(
                  icon: Icon(Icons.delete_sweep_outlined,
                      size: 18, color: theme.colorScheme.error),
                  tooltip: AppLocalizations.of(context).delete,
                  onPressed: widget.onDeleteAll,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        // Minute groups
        ...keys.map((key) => _buildMinuteGroup(context, key, groups[key]!)),
      ],
    );
  }

  Widget _buildMinuteGroup(
      BuildContext context, String minuteKey, List<SharedFile> files) {
    final expanded = _expanded.contains(minuteKey);

    if (files.length == 1) {
      return FileCard(
        file: files.first, onTap: () => widget.onTap(files.first),
        query: widget.query,
        isSelected: widget.selectedIds.contains(files.first.id),
        onLongPress: widget.onToggleSelection != null
            ? () => widget.onToggleSelection!(files.first.id)
            : null,
        onRetry: widget.onRetry != null
            ? () => widget.onRetry!(files.first.id)
            : null,
      );
    }

    final timeStr = DateFormat('HH:mm').format(files.first.receivedAt);
    final theme = Theme.of(context);

    return Column(
      children: [
        // Timestamp header row — shows once, independent of card
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 8, top: 4, bottom: 2),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  timeStr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Timeline dot
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant, width: 2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).items(files.length),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              // Expand/collapse button
              GestureDetector(
                onTap: () => setState(() {
                  if (expanded) {
                    _expanded.remove(minuteKey);
                  } else {
                    _expanded.add(minuteKey);
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
                        expanded ? AppLocalizations.of(context).collapse : AppLocalizations.of(context).expandAll,
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
        // File cards
        if (expanded)
          ...files.map((f) => Padding(
            padding: const EdgeInsets.only(left: 72),
            child: FileCard(
              file: f, onTap: () => widget.onTap(f),
              query: widget.query, showTime: false,
              isSelected: widget.selectedIds.contains(f.id),
              onLongPress: widget.onToggleSelection != null
                  ? () => widget.onToggleSelection!(f.id)
                  : null,
              onRetry: widget.onRetry != null
                  ? () => widget.onRetry!(f.id)
                  : null,
            ),
          )),
      ],
    );
  }
}
