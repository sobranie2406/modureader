import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';

class CustomCSSEditor extends StatefulWidget {
  const CustomCSSEditor({super.key, this.bookKey, this.onApply});
  final String? bookKey;
  final VoidCallback? onApply;

  @override
  State<CustomCSSEditor> createState() => _CustomCSSEditorState();
}

class _CustomCSSEditorState extends State<CustomCSSEditor> {
  final _cssController = TextEditingController();
  final _nameController = TextEditingController();
  late int _index;
  late bool _enabled;
  bool _busy = false;
  String? _error;

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    _loadSelection();
  }

  void _loadSelection() {
    final selection = Prefs().customCssSelection(widget.bookKey);
    _index = selection.index;
    _enabled = selection.enabled;
    _loadProfile();
  }

  void _loadProfile() {
    final profile = Prefs().customCssProfiles[_index];
    _cssController.text = profile.css;
    _nameController.text = profile.name;
    _error = null;
  }

  @override
  void dispose() {
    _cssController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool _validate() {
    final css = _cssController.text;
    // Lightweight editing aid, not a security boundary or full CSS parser.
    final balanced = '{'.allMatches(css).length == '}'.allMatches(css).length;
    setState(() => _error =
        balanced ? null : L10n.of(context).cssValidationUnmatchedBraces);
    return balanced;
  }

  Future<void> _persistDraft() => Prefs().saveCustomCssProfile(
      _index,
      CustomCssProfile(
          name: _nameController.text.trim(), css: _cssController.text));

  CustomCssSelection get _selection =>
      CustomCssSelection(index: _index, enabled: _enabled);

  void _apply() {
    if (widget.onApply != null) {
      widget.onApply!();
    } else {
      epubPlayerKey.currentState?.changeStyle(null);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = _text('保存失败，请重试', 'Could not save. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(int index) => _run(() async {
        if (!_validate()) return;
        // Switching saves the current slot, so edits are not silently discarded.
        await _persistDraft();
        await Prefs().saveCustomCssSelection(
            CustomCssSelection(index: index, enabled: _enabled),
            bookKey: widget.bookKey);
        if (!mounted) return;
        setState(() {
          _index = index;
          _loadProfile();
        });
        _apply();
      });

  Future<void> _toggle(bool value) => _run(() async {
        if (value) {
          if (!_validate()) return;
          await _persistDraft();
        }
        // Disabling always works, even while the draft contains invalid CSS.
        await Prefs().saveCustomCssSelection(
            CustomCssSelection(index: _index, enabled: value),
            bookKey: widget.bookKey);
        if (!mounted) return;
        setState(() => _enabled = value);
        _apply();
      });

  Future<void> _save({bool asDefault = false}) => _run(() async {
        if (!_validate()) return;
        await _persistDraft();
        await Prefs()
            .saveCustomCssSelection(_selection, bookKey: widget.bookKey);
        if (asDefault) await Prefs().saveCustomCssSelection(_selection);
        if (!mounted) return;
        setState(() {});
        _apply();
        AnxToast.show(L10n.of(context).commonSaved);
      });

  Future<void> _followDefault() => _run(() async {
        if (!_validate()) return;
        await _persistDraft();
        await Prefs().clearBookCustomCssSelection(widget.bookKey!);
        if (!mounted) return;
        setState(_loadSelection);
        _apply();
      });

  @override
  Widget build(BuildContext context) {
    final profiles = Prefs().customCssProfiles;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(L10n.of(context).customCssEnabled)),
        Switch(
            key: const ValueKey('custom-css-enabled'),
            value: _enabled,
            onChanged: _busy ? null : _toggle),
      ]),
      Text(
          widget.bookKey == null
              ? _text('默认 CSS 方案', 'Default CSS profile')
              : _text(
                  '本书 CSS 方案（本机记忆）', 'CSS profile for this book (this device)'),
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (var i = 0; i < customCssProfileCount; i++)
          ChoiceChip(
            key: ValueKey('custom-css-profile-$i'),
            label: Text(
                profiles[i].name.isEmpty
                    ? _text('方案 ${i + 1}', 'Profile ${i + 1}')
                    : profiles[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            selected: i == _index,
            onSelected: _busy ? null : (_) => _select(i),
          ),
      ]),
      const SizedBox(height: 8),
      Text(
          _text('共 8 套，可分别用于竖排、横排、精排等。切换会保存当前方案；修改方案会影响使用它的书籍。',
              'Eight reusable profiles for vertical, horizontal or publisher layouts. Switching saves edits; editing a profile affects books using it.'),
          style: Theme.of(context).textTheme.bodySmall),
      if (widget.bookKey != null)
        Wrap(spacing: 8, children: [
          TextButton(
              onPressed: _busy ? null : _followDefault,
              child: Text(_text('跟随默认方案', 'Follow default'))),
          TextButton(
              onPressed: _busy ? null : () => _save(asDefault: true),
              child: Text(_text('设为默认方案', 'Set as default'))),
        ]),
      const SizedBox(height: 12),
      TextField(
          key: const ValueKey('custom-css-name'),
          controller: _nameController,
          enabled: !_busy,
          maxLength: 40,
          decoration: InputDecoration(
              labelText: _text('方案名称', 'Profile name'),
              hintText: _text('例如：竖排古籍、横排小说、精排保留',
                  'e.g. Vertical, Novel, Publisher layout'))),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      SizedBox(
          height: 200,
          child: TextField(
            key: const ValueKey('custom-css-code'),
            controller: _cssController,
            enabled: !_busy,
            maxLines: null,
            expands: true,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            style: const TextStyle(
                fontFamily: 'Courier New', fontSize: 14, height: 1.4),
            decoration: InputDecoration(
                hintText: L10n.of(context).cssEditorHint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(12)),
            textAlignVertical: TextAlignVertical.top,
          )),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 8, children: [
        TextButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _cssController.clear();
                      _error = null;
                    }),
            icon: const Icon(Icons.clear, size: 16),
            label: Text(_text('清空当前代码', 'Clear current CSS'))),
        ElevatedButton.icon(
            onPressed: _busy ? null : () => _save(),
            icon: const Icon(Icons.save, size: 16),
            label: Text(L10n.of(context).cssSaveAndApply)),
      ]),
      const SizedBox(height: 8),
    ]);
  }
}
