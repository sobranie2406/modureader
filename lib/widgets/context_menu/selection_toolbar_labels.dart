import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:flutter/material.dart';

const selectionToolbarIcons = <String, IconData>{
  'query': Icons.manage_search,
  'copy': Icons.content_copy,
  'search': Icons.travel_explore,
  'translate': Icons.translate,
  'dictionary': Icons.menu_book_outlined,
  'narrate': Icons.headphones,
  'note': Icons.edit_note,
  'ai': Icons.auto_awesome,
  'share': Icons.share_outlined,
  'delete': Icons.delete_outline,
  'highlight': Icons.highlight_alt,
  'underline': Icons.format_underline,
  'colors': Icons.palette_outlined,
  'star': Icons.star_outline,
  'heart': Icons.favorite_border,
  'lightbulb': Icons.lightbulb_outline,
  'summary': Icons.summarize_outlined,
  'quote': Icons.format_quote,
  'mindmap': Icons.account_tree_outlined,
};

IconData selectionToolbarIcon(SelectionToolbarItem item) =>
    selectionToolbarIcons[item.icon.isEmpty ? item.action : item.icon] ??
    Icons.auto_awesome;

String selectionToolbarLabel(BuildContext context, SelectionToolbarItem item) {
  if (item.name.trim().isNotEmpty)
    return item.localizedName(Localizations.localeOf(context)).trim();
  final l10n = L10n.of(context);
  return switch (item.action) {
    'query' => ModuStrings.text(context, '综合', 'Look up'),
    'copy' => l10n.contextMenuCopy,
    'search' => l10n.contextMenuSearch,
    'translate' => l10n.contextMenuTranslate,
    'dictionary' => ModuStrings.text(context, '字典', 'Dictionary'),
    'narrate' => l10n.contextMenuNarrate,
    'note' => l10n.contextMenuWriteIdea,
    'ai' => l10n.navBarAI,
    'share' => l10n.contextMenuShare,
    'delete' => l10n.contextMenuDelete,
    'highlight' => l10n.contextMenuHighlight,
    'underline' => l10n.contextMenuUnderline,
    'colors' => ModuStrings.text(context, '批注颜色', 'Colours'),
    _ => ModuStrings.text(context, 'AI 命令', 'AI command'),
  };
}
