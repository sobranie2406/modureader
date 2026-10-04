import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';
import 'document_panel_widgets.dart';

/// Compact Hanvon-style refresh group; only mounted in E-Ink document menus.
class EinkRefreshControls extends StatefulWidget {
  const EinkRefreshControls(
      {super.key, required this.supported, required this.refresh});
  final Future<bool> supported;
  final Future<bool> Function() refresh;

  @override
  State<EinkRefreshControls> createState() => _EinkRefreshControlsState();
}

class _EinkRefreshControlsState extends State<EinkRefreshControls> {
  bool? _supported;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    widget.supported.then((value) {
      if (mounted) setState(() => _supported = value);
    }).catchError((Object _) {
      if (mounted) setState(() => _supported = false);
    });
  }

  void _error() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ModuStrings.text(context, '刷新操作失败，请重试',
            'Refresh operation failed. Please retry.'))));
  }

  Future<void> _setInterval(int pages) async {
    setState(() => _busy = true);
    try {
      await Prefs().setEInkRefreshPages(pages);
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      if (!await widget.refresh()) _error();
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _supported == true && !_busy;
    final pages = Prefs().eInkRefreshPages;
    return DocumentControlRow(
      label: ModuStrings.text(context, '刷新', 'Refresh'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        OutlinedButton.icon(
          onPressed: enabled ? _refresh : null,
          icon: const Icon(Icons.refresh),
          label: Text(ModuStrings.text(context, '立即刷新', 'Refresh now')),
        ),
        if (_supported == true) ...[
          Text(ModuStrings.text(context, '每几页自动全刷', 'Full refresh interval')),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            IconButton(
                tooltip: '-10',
                icon: const Icon(Icons.keyboard_double_arrow_left),
                onPressed: enabled && pages > 0
                    ? () => _setInterval(pages - 10)
                    : null),
            IconButton(
                tooltip: '-1',
                icon: const Icon(Icons.chevron_left),
                onPressed: enabled && pages > 0
                    ? () => _setInterval(pages - 1)
                    : null),
            Text(
                pages == 0 ? ModuStrings.text(context, '关闭', 'Off') : '$pages'),
            IconButton(
                tooltip: '+1',
                icon: const Icon(Icons.chevron_right),
                onPressed: enabled && pages < 100
                    ? () => _setInterval(pages + 1)
                    : null),
            IconButton(
                tooltip: '+10',
                icon: const Icon(Icons.keyboard_double_arrow_right),
                onPressed: enabled && pages < 100
                    ? () => _setInterval(pages + 10)
                    : null),
          ]),
          Text(
              ModuStrings.text(context, '0 为关闭，1–100 页；按原页计数，分格不重复计数',
                  '0 is off; 1–100 original pages. Panels are not counted separately.'),
              style: Theme.of(context).textTheme.bodySmall),
        ] else
          Text(
              _supported == null
                  ? ModuStrings.text(context, '正在检测墨水屏刷新接口…',
                      'Checking E-Ink refresh support…')
                  : ModuStrings.text(context, '此设备未提供受支持的墨水屏刷新接口，请使用系统刷新功能',
                      'No supported E-Ink refresh interface. Use the system refresh control.'),
              style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
