import 'package:flutter/material.dart';

class PagePrefetchControls extends StatelessWidget {
  const PagePrefetchControls({
    super.key,
    required this.title,
    required this.enabled,
    required this.pages,
    required this.pagesLabel,
    required this.fewerPagesTooltip,
    required this.morePagesTooltip,
    required this.onEnabledChanged,
    required this.onPagesChanged,
  });

  final Widget title;
  final bool enabled;
  final int pages;
  final String pagesLabel;
  final String fewerPagesTooltip;
  final String morePagesTooltip;
  final ValueChanged<bool>? onEnabledChanged;
  final ValueChanged<int>? onPagesChanged;

  @override
  Widget build(BuildContext context) {
    final changePages = onPagesChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: title,
          value: enabled,
          onChanged: onEnabledChanged,
        ),
        if (enabled)
          Row(children: [
            Expanded(child: Text(pagesLabel)),
            IconButton(
              tooltip: fewerPagesTooltip,
              onPressed: changePages == null || pages <= 1
                  ? null
                  : () => changePages(pages - 1),
              icon: const Icon(Icons.remove),
            ),
            Semantics(
              liveRegion: true,
              label: pagesLabel,
              child: Text('$pages'),
            ),
            IconButton(
              tooltip: morePagesTooltip,
              onPressed: changePages == null || pages >= 5
                  ? null
                  : () => changePages(pages + 1),
              icon: const Icon(Icons.add),
            ),
          ]),
      ],
    );
  }
}
