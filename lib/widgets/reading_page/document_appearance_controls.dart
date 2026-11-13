import 'package:flutter/material.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/dao/theme.dart';
import 'package:modu_reader/models/read_theme.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/book_player/reading_appearance.dart';
import 'reader_popup.dart';
import 'style_widget.dart';
import 'widgets/bgimg_selector.dart';

/// Reuse ebook palette/background editors without repainting the hidden PDF.
class DocumentAppearanceControls extends StatefulWidget {
  const DocumentAppearanceControls({super.key});
  @override
  State<DocumentAppearanceControls> createState() =>
      _DocumentAppearanceControlsState();
}

class _DocumentAppearanceControlsState
    extends State<DocumentAppearanceControls> {
  late Future<List<ReadTheme>> _themes = themeDao.selectThemes();
  bool _editingColors = false;
  @override
  Widget build(BuildContext context) => Column(children: [
        FutureBuilder<List<ReadTheme>>(
            future: _themes,
            builder: (context, snapshot) => Wrap(spacing: 8, children: [
                  for (final theme in snapshot.data ?? <ReadTheme>[])
                    IconButton.filledTonal(
                        tooltip:
                            ModuStrings.text(context, '选择配色', 'Select palette'),
                        style: IconButton.styleFrom(
                            backgroundColor: Color(
                                int.parse(theme.backgroundColor, radix: 16))),
                        icon: Text('A',
                            style: TextStyle(
                                color: Color(
                                    int.parse(theme.textColor, radix: 16)))),
                        onPressed: () => selectReadingColorTheme(theme,
                            prefs: Prefs(), apply: (_) {})),
                ])),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
              icon: const Icon(Icons.palette_outlined),
              label: Text(ModuStrings.text(
                  context, '背景 / 文字颜色', 'Background / text colors')),
              onPressed: () =>
                  setState(() => _editingColors = !_editingColors)),
          OutlinedButton.icon(
              icon: const Icon(Icons.image_outlined),
              label:
                  Text(ModuStrings.text(context, '背景图片', 'Background image')),
              onPressed: () => showReaderPopup(context,
                  builder: (_) => BgimgSelector(onChanged: () {}))),
        ]),
        if (_editingColors)
          ThemeChangeWidget(
              key: ValueKey(Prefs().readTheme.toJson().toString()),
              readTheme: Prefs().readTheme,
              allowDelete: false,
              setCurrentPage: (_) {},
              applyTheme: (_) {
                if (mounted) setState(() => _themes = themeDao.selectThemes());
              }),
      ]);
}
