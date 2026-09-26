import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/models/css_visual_style.dart';
import 'package:anx_reader/widgets/settings/css_visual_controls.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/css_profile_application.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/config_transfer/custom_css_transfer.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class CustomCSSEditor extends StatefulWidget {
  const CustomCSSEditor(
      {super.key, this.bookKey, this.onApply, this.manage = false});
  final String? bookKey;
  final VoidCallback? onApply;
  final bool manage;

  @override
  State<CustomCSSEditor> createState() => _CustomCSSEditorState();
}

class _CustomCSSEditorState extends State<CustomCSSEditor> {
  final _cssController = TextEditingController();
  final _nameController = TextEditingController();
  final _patternController = TextEditingController();
  Set<int> _active = {};
  bool _highlight = false;
  String _scope = 'all';
  late int _index;
  late bool _enabled;
  bool _busy = false;
  String? _error;
  CssVisualStyle _visual = const CssVisualStyle();

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
    _active = selection.activeIndices.toSet();
    if (widget.manage && Prefs().customCssProfiles[_index].isEmpty) {
      final first = Prefs().customCssProfiles.indexWhere((p) => !p.isEmpty);
      if (first >= 0) _index = first;
    }
    _loadProfile();
  }

  void _loadProfile() {
    final profile = Prefs().customCssProfiles[_index];
    _cssController.text = profile.css;
    _nameController.text = profile.name;
    _patternController.text = profile.pattern;
    _highlight = profile.isHighlight;
    _scope = profile.scope;
    _visual = profile.visual ?? const CssVisualStyle();
    _error = null;
  }

  @override
  void dispose() {
    _cssController.dispose();
    _nameController.dispose();
    _patternController.dispose();
    super.dispose();
  }

  bool _validate() {
    if (_highlight &&
        (_patternController.text.trim().isEmpty ||
            _patternController.text.length > 512)) {
      setState(() => _error =
          _text('请输入 1–512 个字符的正则表达式', 'Enter a regex of 1–512 characters'));
      return false;
    }
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
          name: _nameController.text.trim(),
          css: _cssController.text,
          pattern: _highlight ? _patternController.text : '',
          scope: _scope,
          visual: _visual));

  CustomCssSelection get _selection => CustomCssSelection(
      index: _index, enabled: _enabled, indices: _active.toList());

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
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _error = _text(
            switch (e.message) {
              'Not enough empty CSS slots' => '空位不足，请先导出并删除不再使用的方案。',
              'No profiles to export' => '没有可导出的方案。',
              'CSS file too large' ||
              'CSS file too large (1 MiB maximum)' =>
                '文件过大，请选择不超过 1 MiB 的文件。',
              _ => '导入导出失败：请检查文件格式，支持 CSS 文件和默读方案 JSON。',
            },
            e.message));
      }
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
            CustomCssSelection(
                index: index, enabled: _enabled, indices: _active.toList()),
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
            CustomCssSelection(
                index: _index, enabled: value, indices: _active.toList()),
            bookKey: widget.bookKey);
        if (!mounted) return;
        setState(() => _enabled = value);
        _apply();
      });

  Future<void> _toggleSlot(bool value) => _run(() async {
        if (value && !_validate()) return;
        if (value) await _persistDraft();
        final next = {..._active};
        value ? next.add(_index) : next.remove(_index);
        await Prefs().saveCustomCssSelection(
            CustomCssSelection(
                index: _index, enabled: _enabled, indices: next.toList()),
            bookKey: widget.bookKey);
        if (!mounted) return;
        setState(() => _active = next);
        _apply();
      });

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(title: Text(title), content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(_text('取消', 'Cancel'))),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(_text('确认', 'Confirm'))),
              ])) ??
      false;

  Future<void> _append(List<CustomCssProfile> additions) async {
    final existing = Prefs().customCssProfiles;
    final result = CustomCssTransfer.append(existing, additions);
    final slots = [
      for (var i = 0; i < existing.length; i++)
        if (existing[i].isEmpty) i
    ].take(additions.length).toSet();
    await Prefs().disableCustomCssSlots(slots);
    await Prefs().saveCustomCssProfiles(result);
    final selection = Prefs().customCssSelection(widget.bookKey);
    await Prefs().saveCustomCssSelection(
        CustomCssSelection(
            index: slots.first,
            enabled: selection.enabled,
            indices: selection.activeIndices),
        bookKey: widget.bookKey);
    if (!mounted) return;
    setState(_loadSelection);
    _apply();
  }

  Future<void> _template() => _run(() async {
        if (!_validate()) return;
        await _persistDraft();
        if (!mounted) return;
        final template = await showDialog<CustomCssProfile>(
            context: context,
            builder: (context) => SimpleDialog(
                  title: Text(_text('添加预设模板', 'Add a preset template')),
                  children: [
                    for (final p in customCssTemplates)
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, p),
                        child: Text(p.name),
                      )
                  ],
                ));
        if (template != null) await _append([template]);
      });

  Future<void> _copy() => _run(() async {
        if (!_validate()) return;
        await _persistDraft();
        final p = Prefs().customCssProfiles[_index];
        await _append([
          CustomCssProfile(
              name: '${p.name} ${_text('副本', 'copy')}',
              css: p.css,
              pattern: p.pattern,
              scope: p.scope,
              visual: p.visual)
        ]);
      });

  Future<void> _delete() => _run(() async {
        if (!await _confirm(
            _text('删除当前方案？', 'Delete this profile?'),
            _text('将清空此方案，并在使用它的所有书籍中停用。',
                'This clears the profile and disables it in all books.'))) {
          return;
        }
        await Prefs().disableCustomCssSlots({_index});
        await Prefs().saveCustomCssProfile(_index, const CustomCssProfile());
        if (!mounted) return;
        setState(_loadSelection);
        _apply();
      });

  Future<void> _import() => _run(() async {
        if (!_validate()) return;
        await _persistDraft();
        final picked = await FilePicker.platform.pickFiles(
            type: FileType.custom, allowedExtensions: ['css', 'json']);
        if (picked == null) return;
        final path = picked.files.single.path;
        if (path == null) throw const FormatException('Could not read file');
        final file = File(path);
        if (await file.length() > CustomCssTransfer.maxBytes) {
          throw const FormatException('CSS file too large (1 MiB maximum)');
        }
        final additions = CustomCssTransfer.decode(await file.readAsString(),
            fileName: picked.files.single.name);
        if (!mounted) return;
        if (!await _confirm(
            _text('导入 ${additions.length} 套方案？',
                'Import ${additions.length} profiles?'),
            _text('仅填入空位，默认停用，不覆盖已有方案。请仅导入可信 CSS；启用后其中的图片或字体网址可能发起网络请求。',
                'Only empty slots are used; imported profiles stay disabled. Import trusted CSS only: enabled styles may request remote images or fonts.'))) {
          return;
        }
        await _append(additions);
      });

  Future<void> _export(bool all) => _run(() async {
        if (!_validate()) return;
        await _persistDraft();
        final text = CustomCssTransfer.encode(all
            ? Prefs().customCssProfiles
            : [Prefs().customCssProfiles[_index]]);
        await saveFileToDownload(
            bytes: Uint8List.fromList(utf8.encode(text)),
            fileName: 'modu-css-${DateTime.now().millisecondsSinceEpoch}.json',
            mimeType: 'application/json');
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
    if (!widget.manage) {
      return CssProfileApplication(
          bookKey: widget.bookKey, onApply: widget.onApply);
    }
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
      DropdownButton<int>(
        key: const ValueKey('css-profile-picker'),
        value: _index,
        isExpanded: true,
        items: [
          for (var i = 0; i < profiles.length; i++)
            if (!profiles[i].isEmpty || i == _index)
              DropdownMenuItem(
                  value: i,
                  child: Text(
                      profiles[i].name.isEmpty
                          ? _text('自定义 CSS', 'Custom CSS')
                          : profiles[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis))
        ],
        onChanged: _busy
            ? null
            : (i) {
                if (i != null) _select(i);
              },
      ),
      const SizedBox(height: 8),
      Text(
          _text('按名称管理模板，可同时启用多套；修改会影响使用它的书籍。内置与导入模板默认停用，最多保存 32 套。',
              'Manage named templates; multiple templates can be active. Shared edits affect books using them. Built-ins and imports start disabled. Up to 32 templates.'),
          style: Theme.of(context).textTheme.bodySmall),
      Wrap(spacing: 8, children: [
        TextButton.icon(
            onPressed: _busy ? null : _template,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_text('预设模板', 'Templates'))),
        TextButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      if (!_validate()) return;
                      await _persistDraft();
                      await _append([
                        CustomCssProfile(name: _text('新方案', 'New profile'))
                      ]);
                    }),
            child: Text(_text('新建', 'New'))),
        TextButton(
            onPressed: _busy ? null : _copy,
            child: Text(_text('复制', 'Duplicate'))),
        TextButton(
            onPressed: _busy ? null : _import,
            child: Text(_text('导入', 'Import'))),
        PopupMenuButton<bool>(
            enabled: !_busy,
            onSelected: _export,
            itemBuilder: (_) => [
                  PopupMenuItem(
                      value: false,
                      child: Text(_text('导出当前方案', 'Export current'))),
                  PopupMenuItem(
                      value: true, child: Text(_text('导出全部方案', 'Export all'))),
                ],
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_text('导出', 'Export')))),
        TextButton(
            onPressed: _busy ? null : _delete,
            child: Text(_text('删除', 'Delete'))),
      ]),
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
      Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const ValueKey('custom-css-slot-enabled'),
            title: Text(_text('启用当前方案', 'Enable this profile')),
            subtitle: !_enabled
                ? Text(_text('总开关关闭时，所有方案均不生效', 'The master switch is off'))
                : null,
            value: _active.contains(_index),
            onChanged: _busy ? null : _toggleSlot,
          )),
      Wrap(spacing: 8, children: [
        ChoiceChip(
            label: Text(_text('排版 CSS', 'Layout CSS')),
            selected: !_highlight,
            onSelected:
                _busy ? null : (_) => setState(() => _highlight = false)),
        ChoiceChip(
            label: Text(_text('正则高亮', 'Regex highlight')),
            selected: _highlight,
            onSelected:
                _busy ? null : (_) => setState(() => _highlight = true)),
      ]),
      TextField(
          key: const ValueKey('custom-css-name'),
          controller: _nameController,
          enabled: !_busy,
          maxLength: 40,
          decoration: InputDecoration(
              labelText: _text('方案名称', 'Profile name'),
              hintText: _text('例如：竖排古籍、横排小说、精排保留',
                  'e.g. Vertical, Novel, Publisher layout'))),
      if (_highlight) ...[
        TextField(
            key: const ValueKey('custom-css-pattern'),
            controller: _patternController,
            enabled: !_busy,
            maxLength: 512,
            decoration: InputDecoration(
                labelText: _text('正则表达式（JavaScript，无需 / /）',
                    'Regular expression (JavaScript, no / /)'))),
      ],
      DropdownButton<String>(
          value: _scope,
          isExpanded: true,
          items: [
            DropdownMenuItem(
                value: 'all', child: Text(_text('作用范围：全部', 'Scope: All'))),
            DropdownMenuItem(
                value: 'title',
                child: Text(_text('作用范围：标题', 'Scope: Headings'))),
            DropdownMenuItem(
                value: 'body', child: Text(_text('作用范围：正文', 'Scope: Body'))),
          ],
          onChanged: _busy ? null : (value) => setState(() => _scope = value!)),
      IgnorePointer(
          ignoring: _busy,
          child: CssVisualControls(
            style: _visual,
            highlight: _highlight,
            onChanged: (style) => setState(() => _visual = style),
          )),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ExpansionTile(
        key: ValueKey('css-code-editor-$_index'),
        title: Text(_text('自定义 CSS 代码（高级）', 'Custom CSS code (advanced)')),
        initiallyExpanded: _cssController.text.isNotEmpty,
        children: [
          Text(_highlight
              ? _text('局部高亮填写 CSS 声明，不加选择器和花括号。',
                  'For highlights, enter declarations without selectors or braces.')
              : _text('保留原有代码，附加在图形参数之后；作用范围由代码选择器决定。',
                  'Original code is preserved and follows visual settings. Code selectors determine its scope.')),
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
        ],
      ),
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
            label: Text(_text('保存模板', 'Save template'))),
      ]),
      const SizedBox(height: 8),
    ]);
  }
}
