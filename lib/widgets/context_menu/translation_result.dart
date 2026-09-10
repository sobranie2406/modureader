import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Translation is reading text, not a presentation: keep model-generated
/// Markdown headings compact without changing AI chat styles elsewhere.
class TranslationResult extends StatelessWidget {
  const TranslationResult({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body =
        theme.textTheme.bodyMedium!.copyWith(fontSize: 16, height: 1.5);
    final heading = body.copyWith(fontSize: 18, fontWeight: FontWeight.w600);
    return DefaultTextStyle(
      style: body,
      child: GptMarkdownTheme(
        gptThemeData: GptMarkdownTheme.of(context).copyWith(
          h1: heading,
          h2: heading,
          h3: heading,
          h4: heading.copyWith(fontSize: 16),
          h5: heading.copyWith(fontSize: 16),
          h6: heading.copyWith(fontSize: 16),
        ),
        child: child,
      ),
    );
  }
}
