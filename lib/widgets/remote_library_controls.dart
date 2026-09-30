import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/remote_library/library_view_options.dart';
import 'package:flutter/material.dart';

class RemoteLibraryControls extends StatelessWidget {
  const RemoteLibraryControls(
      {super.key, required this.options, required this.onChanged});
  final LibraryViewOptions options;
  final ValueChanged<LibraryViewOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    String sortLabel(LibrarySortField field) => switch (field) {
          LibrarySortField.name =>
            ModuStrings.text(context, '书名 / 文件名', 'Book / file name'),
          LibrarySortField.createdAt =>
            ModuStrings.text(context, '添加时间', 'Date added'),
          LibrarySortField.modifiedAt =>
            ModuStrings.text(context, '修改时间', 'Date modified'),
          LibrarySortField.size =>
            ModuStrings.text(context, '文件大小', 'File size'),
        };
    String filterLabel(LibraryFileFilter filter) => switch (filter) {
          LibraryFileFilter.all =>
            ModuStrings.text(context, '全部文件', 'All files'),
          LibraryFileFilter.books =>
            ModuStrings.text(context, '仅书籍', 'Books only'),
          _ => filter.name.toUpperCase(),
        };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<LibrarySortField>(
              key: const ValueKey('library-sort-field'),
              value: options.sort,
              items: [
                for (final field in LibrarySortField.values)
                  DropdownMenuItem(value: field, child: Text(sortLabel(field)))
              ],
              onChanged: (value) {
                if (value != null) onChanged(options.copyWith(sort: value));
              },
            ),
            OutlinedButton.icon(
              key: const ValueKey('library-sort-direction'),
              onPressed: () =>
                  onChanged(options.copyWith(ascending: !options.ascending)),
              icon: Icon(
                  options.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 18),
              label: Text(options.ascending
                  ? ModuStrings.text(context, '升序', 'Ascending')
                  : ModuStrings.text(context, '降序', 'Descending')),
            ),
            DropdownButton<LibraryFileFilter>(
              key: const ValueKey('library-file-filter'),
              value: options.filter,
              items: [
                for (final filter in LibraryFileFilter.values)
                  DropdownMenuItem(
                      value: filter, child: Text(filterLabel(filter)))
              ],
              onChanged: (value) {
                if (value != null) onChanged(options.copyWith(filter: value));
              },
            ),
          ]),
      if (options.sort == LibrarySortField.createdAt ||
          options.sort == LibrarySortField.modifiedAt)
        Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              options.sort == LibrarySortField.createdAt
                  ? ModuStrings.text(context, '添加时间使用服务器创建时间；未提供的排在末尾。',
                      'Date added uses server creation time; missing dates sort last.')
                  : ModuStrings.text(context, '使用服务器修改时间；未提供的排在末尾。',
                      'Uses server modification time; missing dates sort last.'),
              style: Theme.of(context).textTheme.bodySmall,
            )),
    ]);
  }
}
