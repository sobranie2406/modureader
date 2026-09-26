import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:flutter/material.dart';

/// Reader UI only changes application/selection, never edits shared templates.
class CssProfileApplication extends StatefulWidget {
  const CssProfileApplication({super.key, this.bookKey, this.onApply});
  final String? bookKey;
  final VoidCallback? onApply;
  @override
  State<CssProfileApplication> createState() => _CssProfileApplicationState();
}

class _CssProfileApplicationState extends State<CssProfileApplication> {
  bool _busy = false;
  String? _error;
  Future<void> save(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) {
        if (widget.onApply != null) {
          widget.onApply!();
        } else {
          epubPlayerKey.currentState?.changeStyle(null);
        }
      }
    } catch (_) {
      if (mounted) _error = '保存失败 / Could not save';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        final prefs = Prefs();
        final profiles = prefs.customCssProfiles;
        final selection = prefs.customCssSelection(widget.bookKey);
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        Future<void> change(bool enabled, List<int> indices, int index) =>
            save(() => prefs.saveCustomCssSelection(
                CustomCssSelection(
                    index: index, enabled: enabled, indices: indices),
                bookKey: widget.bookKey));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(zh ? '应用 CSS 模板' : 'Apply CSS templates')),
            Switch(
                key: const ValueKey('custom-css-enabled'),
                value: selection.enabled,
                onChanged: _busy
                    ? null
                    : (v) =>
                        change(v, selection.activeIndices, selection.index))
          ]),
          Text(zh
              ? '选择即应用，可叠加多套。参数与代码请在“设置 → CSS 设置”中调整。'
              : 'Select to apply multiple templates. Edit parameters and code in Settings → CSS settings.'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (var i = 0; i < profiles.length; i++)
              if (!profiles[i].isEmpty)
                FilterChip(
                    key: ValueKey('apply-css-$i'),
                    label: Text(profiles[i].name.isEmpty
                        ? (zh ? '自定义 CSS' : 'Custom CSS')
                        : profiles[i].name),
                    selected: selection.activeIndices.contains(i),
                    onSelected: _busy
                        ? null
                        : (v) {
                            final next = selection.activeIndices.toSet();
                            v ? next.add(i) : next.remove(i);
                            change(
                                v ? true : selection.enabled, next.toList(), i);
                          }),
          ]),
          if (widget.bookKey != null)
            TextButton(
                onPressed: _busy
                    ? null
                    : () => save(() =>
                        prefs.clearBookCustomCssSelection(widget.bookKey!)),
                child: Text(zh ? '跟随默认模板' : 'Follow default templates')),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]);
      });
}
