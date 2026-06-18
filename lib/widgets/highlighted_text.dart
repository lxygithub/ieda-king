import 'package:flutter/material.dart';

/// Render text with search matches highlighted.
/// Supports exact substring highlight + per-char fuzzy highlight fallback.
class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    final theme = Theme.of(context);
    final highlightStyle = (style ?? theme.textTheme.bodyMedium)?.copyWith(
      color: Colors.blue.shade700,
      backgroundColor: Colors.blue.shade50,
      fontWeight: FontWeight.w600,
    );

    return Text.rich(
      _buildSpans(text, query, style ?? DefaultTextStyle.of(context).style, highlightStyle),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.ellipsis,
    );
  }

  TextSpan _buildSpans(
      String text, String query, TextStyle base, TextStyle? highlight) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    // Try exact substring match first
    final exactIdx = lowerText.indexOf(lowerQuery);
    if (exactIdx != -1) {
      return _spanFromExact(text, exactIdx, lowerQuery.length, base, highlight);
    }

    // Fall back to fuzzy char match
    final matchedIndices = _fuzzyMatchIndices(lowerText, lowerQuery);
    if (matchedIndices.isEmpty) {
      return TextSpan(text: text, style: base);
    }

    return _spanFromIndices(text, matchedIndices, base, highlight);
  }

  TextSpan _spanFromExact(String text, int start, int len, TextStyle base, TextStyle? hl) {
    final children = <InlineSpan>[];
    if (start > 0) {
      children.add(TextSpan(text: text.substring(0, start), style: base));
    }
    children.add(TextSpan(text: text.substring(start, start + len), style: hl));
    if (start + len < text.length) {
      children.add(TextSpan(text: text.substring(start + len), style: base));
    }
    return TextSpan(children: children);
  }

  TextSpan _spanFromIndices(
      String text, Set<int> indices, TextStyle base, TextStyle? hl) {
    final children = <InlineSpan>[];
    for (int i = 0; i < text.length; i++) {
      children.add(TextSpan(
        text: text[i],
        style: indices.contains(i) ? hl : base,
      ));
    }
    return TextSpan(children: children);
  }

  /// Find indices where query chars appear in order in text.
  Set<int> _fuzzyMatchIndices(String text, String query) {
    final indices = <int>{};
    int ti = 0;
    for (int i = 0; i < text.length && ti < query.length; i++) {
      if (text[i] == query[ti]) {
        indices.add(i);
        ti++;
      }
    }
    // Only return indices if all query chars were matched
    return ti == query.length ? indices : {};
  }
}
