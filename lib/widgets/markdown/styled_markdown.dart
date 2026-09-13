import 'package:anx_reader/widgets/markdown/selection_control.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// A custom Markdown widget with theme-aware styling.
/// This widget provides better contrast and readability in both light and dark modes,
/// especially for blockquotes and code blocks that appear in AI chat responses.
class StyledMarkdown extends StatefulWidget {
  final String data;
  final bool selectable;
  final double? fontSize;

  const StyledMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.fontSize,
  });

  @override
  State<StyledMarkdown> createState() => _StyledMarkdownState();
}

class _StyledMarkdownState extends State<StyledMarkdown> {
  Widget? _cached;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cached = null;
  }

  @override
  void didUpdateWidget(StyledMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.fontSize != widget.fontSize ||
        oldWidget.selectable != widget.selectable) {
      _cached = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cached != null) return _cached!;
    final theme = Theme.of(context);
    final requestedSize = widget.fontSize;
    final baseFontSize = requestedSize == null
        ? null
        : requestedSize.isFinite && requestedSize >= 10 && requestedSize <= 24
            ? requestedSize
            : 14.0;
    final body = theme.textTheme.bodyMedium!
        .copyWith(fontSize: baseFontSize, height: 1.5);
    Widget result = GptMarkdown(widget.data,
        followLinkColor: true,
        style: baseFontSize != null ? body : null,
        onLinkTap: (href, text) =>
            launchUrlString(href, mode: LaunchMode.externalApplication),
        linkBuilder: (context, text, url, style) => Text.rich(
              text,
              style: style.copyWith(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ));
    // Explicit AI font sizes govern headings too. Without an explicit size,
    // retain an enclosing translation/result theme's own typography.
    if (baseFontSize != null) {
      TextStyle heading(double extra) => body.copyWith(
          fontSize: baseFontSize + extra, fontWeight: FontWeight.w600);
      result = DefaultTextStyle(
          style: body,
          child: GptMarkdownTheme(
              gptThemeData: GptMarkdownTheme.of(context).copyWith(
                  h1: heading(4),
                  h2: heading(3),
                  h3: heading(2),
                  h4: heading(1),
                  h5: heading(0),
                  h6: heading(0)),
              child: result));
    }
    if (widget.selectable) {
      result = SelectableRegion(
          selectionControls: selectionControls(), child: result);
    }
    // Reuse unchanged history/tool/reasoning Markdown subtrees as tokens arrive.
    // Theme changes invalidate this cache via didChangeDependencies.
    return _cached = result;
  }
}
