import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'reader_menu_group.dart';
import 'dart:convert';
import 'package:modu_reader/widgets/common/app_scroll_behavior.dart';
import 'dart:math' as math;
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/document_page_layout.dart';
import 'widget_title.dart';
import 'package:flutter/material.dart';

/// Draft-only editing. Neither dragging nor switching odd/even pages writes
/// preferences; a successful explicit confirmation is the sole write path.
class DocumentLayoutEditor extends StatefulWidget {
  const DocumentLayoutEditor(
      {super.key,
      required this.initial,
      required this.page,
      required this.total,
      required this.info,
      required this.render,
      required this.cancelRender,
      required this.save,
      this.panelReading,
      this.setPanelReading});
  final DocumentLayoutConfig initial;
  final bool? panelReading;
  final Future<void> Function(bool)? setPanelReading;
  final int page, total;
  final Future<Map<String, dynamic>> Function(int?) info;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) render;
  final VoidCallback cancelRender;
  final Future<void> Function(DocumentLayoutConfig) save;

  @override
  State<DocumentLayoutEditor> createState() => _DocumentLayoutEditorState();
}

class _DocumentLayoutEditorState extends State<DocumentLayoutEditor> {
  late final Map<DocumentLayoutScope, DocumentPageLayout> _draft;
  late bool _panelReading = widget.panelReading ?? true;
  bool _changingPanelReading = false;
  final _dirty = <DocumentLayoutScope>{};
  bool _paired = false,
      _busy = true,
      _failed = false,
      _saving = false,
      _saveFailed = false;
  DocumentLayoutScope _scope = DocumentLayoutScope.current;
  int _previewPage = 0, _generation = 0;
  double _aspect = 1;
  MemoryImage? _image;
  double get _autoMargin => _layout.autoMargin * 100;
  bool _detecting = false;
  String? _cropNotice;
  final _controlsScroll = ScrollController();

  DocumentPageLayout get _layout => _draft[_scope]!;
  String tr(String zh, String en) => ModuStrings.text(context, zh, en);

  @override
  void initState() {
    super.initState();
    final config = widget.initial;
    _draft = {
      DocumentLayoutScope.current: config.forPage(widget.page),
      DocumentLayoutScope.all: config.all ?? const DocumentPageLayout(),
      DocumentLayoutScope.odd:
          config.odd ?? config.all ?? const DocumentPageLayout(),
      DocumentLayoutScope.even:
          config.even ?? config.all ?? const DocumentPageLayout(),
    };
    _loadPreview();
  }

  @override
  void dispose() {
    _generation++;
    widget.cancelRender();
    _image?.evict();
    _controlsScroll.dispose();
    super.dispose();
  }

  int get _targetPage {
    if (!_paired) return widget.page;
    final wantsEvenIndex = _scope == DocumentLayoutScope.odd;
    if (widget.page.isEven == wantsEvenIndex) return widget.page;
    return widget.page + 1 < widget.total ? widget.page + 1 : widget.page - 1;
  }

  Future<void> _loadPreview() async {
    final generation = ++_generation, page = _targetPage;
    widget.cancelRender();
    _image?.evict();
    setState(() {
      _image = null;
      _previewPage = page;
      _busy = true;
      _failed = false;
      _detecting = false;
      _cropNotice = null;
    });
    try {
      final metadata = await widget.info(page);
      if (!mounted || generation != _generation) return;
      final w = (metadata['width'] as num).toDouble(),
          h = (metadata['height'] as num).toDouble();
      if (!w.isFinite ||
          !h.isFinite ||
          w <= 0 ||
          h <= 0 ||
          metadata['page'] != page) {
        throw const FormatException('Invalid preview page');
      }
      final result = await widget.render({
        'page': page,
        'rotation': 0,
        'region': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
        'width': 1000,
        'height': 1200,
        if (_layout.autoCrop) 'analyzeCrop': true,
        if (_layout.autoCrop) 'margin': _layout.autoMargin,
      });
      if (!mounted || generation != _generation) return;
      final data = result['dataUrl'] as String;
      if (!data.startsWith('data:image/png;base64,')) {
        throw const FormatException('Invalid preview image');
      }
      final image = MemoryImage(
          base64Decode(data.substring('data:image/png;base64,'.length)));
      setState(() {
        if (_layout.autoCrop) {
          final detection = result['cropDetection'];
          _draft[_scope] = DocumentPageLayout.fromJson({
            ..._layout.toJson(),
            'crop': detection is Map && detection['detected'] == true
                ? detection['crop']
                : {'x': 0, 'y': 0, 'width': 1, 'height': 1},
          });
        }
        _image = image;
        _aspect = w / h;
        _previewPage = page;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  void _change(DocumentPageLayout layout) {
    layout.validate();
    setState(() {
      _draft[_scope] = layout;
      _dirty.add(_scope);
      _saveFailed = false;
    });
  }

  Future<void> _autoCrop() async {
    if (_busy || _failed || _saving || _detecting) return;
    // The automatic action defaults to the whole document. Individual manual
    // page/parity overrides remain available through the scope selector.
    if (!_paired &&
        _scope == DocumentLayoutScope.current &&
        !_layout.autoCrop) {
      final current = _layout;
      setState(() {
        _scope = DocumentLayoutScope.all;
        _draft[_scope] = current;
      });
    }
    final generation = ++_generation, scope = _scope, page = _previewPage;
    setState(() {
      _detecting = true;
      _cropNotice = null;
    });
    try {
      final result = await widget.render({
        'page': page,
        'rotation': 0,
        'region': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
        'width': 1000,
        'height': 1200,
        'analyzeCrop': true,
        'margin': _autoMargin / 100
      });
      if (!mounted || generation != _generation || scope != _scope) return;
      final detection = result['cropDetection'];
      if (detection is! Map || detection['crop'] is! Map) {
        throw const FormatException('Invalid crop result');
      }
      final crop = DocumentPageLayout.fromJson({
        ..._layout.toJson(),
        'crop': detection['crop'],
        'autoCrop': true,
        'autoMargin': _autoMargin / 100
      });
      _change(crop);
      setState(() => _cropNotice = detection['detected'] == true
          ? tr("所选范围内的每页将自动识别裁边。",
              "Detect crop edges separately for each page in the selected range.")
          : tr("请手动调整裁边框。", "Adjust the crop frame manually."));
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _cropNotice = tr('自动裁边失败，原草稿未改动，请重试。',
            'Auto crop failed. Draft unchanged. Please retry.'));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _detecting = false);
      }
    }
  }

  void _switchScope(DocumentLayoutScope scope) {
    setState(() => _scope = scope);
    _loadPreview();
  }

  Future<void> _save() async {
    if (_saving || _busy || _failed || _detecting) return;
    var config = widget.initial;
    final scopes = _paired
        ? _dirty
            .where((scope) =>
                scope == DocumentLayoutScope.odd ||
                scope == DocumentLayoutScope.even)
            .toSet()
        : {_scope};
    if (scopes.isEmpty) scopes.add(_scope);
    for (final scope in scopes) {
      config = config.apply(scope, widget.page, _draft[scope]!);
    }
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await widget.save(config);
      if (!mounted) return;
      // PopScope is released on the next frame, so Android back cannot race a
      // pending save and make a cancelled draft appear to have been committed.
      setState(() => _saving = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, config);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }

  void _move(Offset delta, Size size, String corner) {
    if (_saving || _busy || _failed || _detecting) return;
    final r = _layout.crop,
        dx = delta.dx / size.width,
        dy = delta.dy / size.height;
    final minW = math.min(.03, r.width), minH = math.min(.03, r.height);
    Rect rect;
    if (corner == 'move') {
      rect = Rect.fromLTWH(
          (r.left + dx).clamp(0.0, math.max(0.0, 1 - r.width)),
          (r.top + dy).clamp(0.0, math.max(0.0, 1 - r.height)),
          r.width,
          r.height);
    } else {
      rect = Rect.fromLTRB(
          corner.endsWith('l')
              ? (r.left + dx).clamp(0.0, r.right - minW)
              : r.left,
          corner.startsWith('t')
              ? (r.top + dy).clamp(0.0, r.bottom - minH)
              : r.top,
          corner.endsWith('r')
              ? (r.right + dx).clamp(r.left + minW, 1.0)
              : r.right,
          corner.startsWith('b')
              ? (r.bottom + dy).clamp(r.top + minH, 1.0)
              : r.bottom);
    }
    _change(_layout.copyWith(crop: rect, autoCrop: false));
    setState(() => _cropNotice = null);
  }

  void _setMargin(double value, {bool refresh = false}) {
    _change(_layout.copyWith(autoMargin: value.clamp(0, 20) / 100));
    if (refresh && _layout.autoCrop) _autoCrop();
  }

  Widget _controls() => AppScrollbar(
      controller: _controlsScroll,
      child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
              controller: _controlsScroll,
              padding: const EdgeInsets.fromLTRB(26, 12, 26, 12),
              child: ReaderMenuGroup(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.setPanelReading != null)
                          SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title:
                                  Text(tr('按裁边与分格阅读', 'Read cropped panels')),
                              value: _panelReading,
                              onChanged: _saving || _changingPanelReading
                                  ? null
                                  : (value) async {
                                      setState(
                                          () => _changingPanelReading = true);
                                      try {
                                        await widget.setPanelReading!(value);
                                        if (mounted) {
                                          setState(() => _panelReading = value);
                                        }
                                      } catch (_) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(tr('版式切换失败，请重试',
                                                      'Could not change layout. Please retry.'))));
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() =>
                                              _changingPanelReading = false);
                                        }
                                      }
                                    }),
                        Wrap(spacing: 8, children: [
                          ChoiceChip(
                              label: Text(tr('常规', 'General')),
                              selected: !_paired,
                              onSelected: _saving
                                  ? null
                                  : (_) {
                                      setState(() => _paired = false);
                                      _switchScope(DocumentLayoutScope.current);
                                    }),
                          ChoiceChip(
                              label: Text(tr('奇偶页', 'Odd / even')),
                              selected: _paired,
                              onSelected: _saving
                                  ? null
                                  : (_) {
                                      setState(() => _paired = true);
                                      _switchScope(widget.page.isEven
                                          ? DocumentLayoutScope.odd
                                          : DocumentLayoutScope.even);
                                    }),
                        ]),
                        Wrap(
                            key: const ValueKey('layout-scope'),
                            spacing: 8,
                            runSpacing: 8,
                            children: (_paired
                                    ? [
                                        DocumentLayoutScope.odd,
                                        DocumentLayoutScope.even
                                      ]
                                    : [
                                        DocumentLayoutScope.current,
                                        DocumentLayoutScope.all
                                      ])
                                .map((scope) => ChoiceChip(
                                    key: ValueKey('layout-scope-${scope.name}'),
                                    selected: _scope == scope,
                                    onSelected: _saving ||
                                            (scope ==
                                                    DocumentLayoutScope.even &&
                                                widget.total <= 1)
                                        ? null
                                        : (_) => _switchScope(scope),
                                    label: Text(switch (scope) {
                                      DocumentLayoutScope.current =>
                                        tr('仅当前原页', 'Current original page'),
                                      DocumentLayoutScope.all =>
                                        tr('全书', 'Whole document'),
                                      DocumentLayoutScope.odd =>
                                        tr('奇数页', 'Odd pages'),
                                      DocumentLayoutScope.even =>
                                        tr('偶数页', 'Even pages'),
                                    })))
                                .toList()),
                        SwitchListTile.adaptive(
                            key: const ValueKey('auto-crop-enabled'),
                            contentPadding: EdgeInsets.zero,
                            title: SettingHelp(
                                title: Text(tr('逐页自动裁边', 'Per-page auto crop')),
                                description: Text(
                                    tr("自动识别每页裁边；拖动裁边框可改为手动。",
                                        "Detect page edges automatically, or drag the crop frame to adjust them."),
                                    style:
                                        Theme.of(context).textTheme.bodySmall)),
                            value: _layout.autoCrop,
                            onChanged: _saving || _busy || _failed || _detecting
                                ? null
                                : (value) {
                                    if (value) {
                                      _autoCrop();
                                    } else {
                                      _change(
                                          _layout.copyWith(autoCrop: false));
                                      setState(() => _cropNotice = null);
                                    }
                                  }),
                        OutlinedButton.icon(
                            key: const ValueKey('auto-crop'),
                            onPressed: _saving || _busy || _failed || _detecting
                                ? null
                                : _autoCrop,
                            icon: const Icon(Icons.auto_fix_high),
                            label: Text(_detecting
                                ? tr('识别边界中…', 'Detecting borders…')
                                : tr('自动裁边', 'Auto crop'))),
                        Text(
                            '${tr('裁边留白（原页宽高百分比）', 'Crop margin (% of page dimensions)')} ${_autoMargin.round()}%'),
                        Row(children: [
                          IconButton(
                              tooltip: tr('减少留白', 'Less margin'),
                              onPressed:
                                  _saving || _detecting || _busy || _failed
                                      ? null
                                      : () => _setMargin(_autoMargin - 1,
                                          refresh: true),
                              icon: const Icon(Icons.remove)),
                          Expanded(
                              child: Slider(
                                  key: const ValueKey('crop-margin'),
                                  value: _autoMargin,
                                  min: 0,
                                  max: 20,
                                  divisions: 20,
                                  onChanged:
                                      _saving || _detecting || _busy || _failed
                                          ? null
                                          : (value) => _setMargin(value),
                                  onChangeEnd: _saving ||
                                          _detecting ||
                                          _busy ||
                                          _failed
                                      ? null
                                      : (value) =>
                                          _setMargin(value, refresh: true))),
                          IconButton(
                              tooltip: tr('增加留白', 'More margin'),
                              onPressed:
                                  _saving || _detecting || _busy || _failed
                                      ? null
                                      : () => _setMargin(_autoMargin + 1,
                                          refresh: true),
                              icon: const Icon(Icons.add)),
                        ]),
                        SettingHelp(
                            title: Text(ModuStrings.text(
                                context, "裁边留白", "Crop margins")),
                            description: Text(
                                tr("增加留白可保留页码和脚注。",
                                    "Add margins to keep page numbers and footnotes."),
                                style: Theme.of(context).textTheme.bodySmall)),
                        if (_cropNotice != null) Text(_cropNotice!),
                        Wrap(spacing: 8, children: [
                          ActionChip(
                              label: Text(tr(
                                  '漫画：右至左双页', 'Manga: right-to-left spread')),
                              onPressed: _saving || _detecting
                                  ? null
                                  : () => _change(_layout.copyWith(
                                      preset: 'horizontal2',
                                      order: 'row-rtl'))),
                          ActionChip(
                              label: Text(tr('漫画：单页', 'Comic: single page')),
                              onPressed: _saving || _detecting
                                  ? null
                                  : () => _change(_layout.copyWith(
                                      preset: 'single', order: 'row-ltr'))),
                          ActionChip(
                              label: Text(tr('论文：双栏', 'Paper: two columns')),
                              onPressed: _saving || _detecting
                                  ? null
                                  : () => _change(_layout.copyWith(
                                      preset: 'horizontal2',
                                      order: 'column-ltr'))),
                        ]),
                        Text(tr('分格数量', 'Grid layout')),
                        Wrap(
                            key: const ValueKey('layout-grid'),
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                DocumentPageLayout.grids.entries.map((entry) {
                              final preset = entry.key;
                              final (columns, rows) = entry.value;
                              final label = switch (preset) {
                                'horizontal2' => tr('水平双格', 'Two columns'),
                                'vertical2' => tr('垂直双格', 'Two rows'),
                                'four' => tr('四格', 'Four panels'),
                                'horizontal6' =>
                                  tr('水平六格', 'Six panels · 3 columns'),
                                'vertical6' =>
                                  tr('垂直六格', 'Six panels · 2 columns'),
                                'nine' => tr('九格', 'Nine panels'),
                                _ => tr('单页', 'Single page'),
                              };
                              return ChoiceChip(
                                key: ValueKey('layout-grid-$preset'),
                                selected: _layout.preset == preset,
                                showCheckmark: false,
                                label: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ExcludeSemantics(
                                          child: SizedBox(
                                              width: 64,
                                              height: 72,
                                              child: Column(children: [
                                                for (var row = 0;
                                                    row < rows;
                                                    row++)
                                                  Expanded(
                                                      child: Row(children: [
                                                    for (var col = 0;
                                                        col < columns;
                                                        col++)
                                                      Expanded(
                                                          child: Container(
                                                        margin: const EdgeInsets
                                                            .all(1),
                                                        decoration: BoxDecoration(
                                                            border: Border.all(
                                                                color: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .onSurface)),
                                                      )),
                                                  ])),
                                              ]))),
                                      const SizedBox(height: 4),
                                      Text(label),
                                    ]),
                                onSelected: _saving || _detecting
                                    ? null
                                    : (_) => _change(
                                        _layout.copyWith(preset: preset)),
                              );
                            }).toList()),
                        Text(tr(
                            '阅读顺序（图中数字）', 'Reading order (numbers on page)')),
                        DropdownButton<String>(
                            key: const ValueKey('layout-order'),
                            isExpanded: true,
                            value: _layout.order,
                            items: DocumentPageLayout.orders
                                .map((order) => DropdownMenuItem(
                                    value: order,
                                    child: Text(switch (order) {
                                      'row-rtl' =>
                                        tr('逐行：右至左', 'Rows: right to left'),
                                      'column-ltr' =>
                                        tr('逐列：左至右', 'Columns: left to right'),
                                      'column-rtl' =>
                                        tr('逐列：右至左', 'Columns: right to left'),
                                      _ => tr('逐行：左至右', 'Rows: left to right'),
                                    })))
                                .toList(),
                            onChanged: _saving || _detecting
                                ? null
                                : (value) {
                                    if (value != null) {
                                      _change(_layout.copyWith(order: value));
                                    }
                                  }),
                        SettingHelp(
                            title: Text(ModuStrings.text(
                                context, "调整裁边", "Adjust crop")),
                            description: Text(tr("拖动四角调整裁边，拖动框内移动。",
                                "Drag a corner to resize the crop, or drag inside to move it."))),
                        const SizedBox(height: 8),
                        SettingHelp(
                            title: Text(ModuStrings.text(
                                context, "应用范围", "Page range")),
                            description: Text(
                                _paired
                                    ? tr("分别调整奇数页和偶数页。",
                                        "Adjust odd and even pages separately.")
                                    : tr("应用到全书会替换已有裁边设置。",
                                        "Applying to the whole book replaces existing crop settings."),
                                style: Theme.of(context).textTheme.bodySmall)),
                      ])))));

  Widget _canvas() => LayoutBuilder(builder: (context, constraints) {
        if (_busy) {
          return const Center(
              child: EinkStaticIndicator(child: CircularProgressIndicator()));
        }
        if (_failed || _image == null) {
          return Center(
              child: TextButton(
                  onPressed: _loadPreview,
                  child: Text(tr('预览失败，点击重试', 'Preview failed. Retry'))));
        }
        final w = math.max(
            1.0,
            math.min(constraints.maxWidth - 48,
                (constraints.maxHeight - 48) * _aspect));
        final size = Size(w, w / _aspect), r = _layout.crop;
        return Center(
            child: SizedBox(
                // Keep the entire 44px hit target INSIDE the parent box. A
                // Stack with clip:none paints outside but cannot hit-test there.
                width: size.width + 48,
                height: size.height + 48,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                      left: 24,
                      right: 24,
                      top: 24,
                      bottom: 24,
                      child: Image(
                          image: _image!,
                          fit: BoxFit.fill,
                          errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                  tr('图像解码失败', 'Image decoding failed'))))),
                  Positioned.fill(
                      left: 24,
                      right: 24,
                      top: 24,
                      bottom: 24,
                      child: IgnorePointer(
                          child: CustomPaint(
                              painter: DocumentCropPainter(_layout,
                                  Theme.of(context).colorScheme.primary,
                                  fontFamily: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.fontFamily)))),
                  Positioned(
                      left: 24 + r.left * w,
                      top: 24 + r.top * size.height,
                      width: r.width * w,
                      height: r.height * size.height,
                      child: GestureDetector(
                          key: const ValueKey('crop-move'),
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (d) => _move(d.delta, size, 'move'))),
                  for (final entry in {
                    'tl': r.topLeft,
                    'tr': r.topRight,
                    'bl': r.bottomLeft,
                    'br': r.bottomRight
                  }.entries)
                    Positioned(
                        left: 24 + entry.value.dx * w - 22,
                        top: 24 + entry.value.dy * size.height - 22,
                        child: Semantics(
                            label: tr('调整裁边', 'Resize crop'),
                            child: GestureDetector(
                                key: ValueKey('crop-${entry.key}'),
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (d) =>
                                    _move(d.delta, size, entry.key),
                                child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: Center(
                                        child: Container(
                                            width: 14,
                                            height: 14,
                                            decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                border: Border.all(
                                                    color: Colors.white,
                                                    width: 2),
                                                shape: BoxShape.circle))))))),
                ])));
      });

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: Dialog.fullscreen(
          child: SafeArea(
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(tr('裁边与分格', 'Crop and panels'),
                  style: readerSubmenuTitleStyle(context))),
          Text(
              '${tr('预览原页', 'Original preview page')} ${(_busy ? _targetPage : _previewPage) + 1} / ${widget.total}'),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                      child: KeyedSubtree(
                          key: const ValueKey('crop-preview'),
                          child: _canvas())),
                  SizedBox(
                      key: const ValueKey('crop-options'),
                      height: math.min(320, constraints.maxHeight * .45),
                      child: _controls()),
                ]);
          })),
          if (_saveFailed)
            Text(tr('保存失败，未应用。请重试。', 'Save failed. Not applied. Please retry.'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SettingHelp(
                  title: Text(ModuStrings.text(context, "应用裁边", "Apply crop")),
                  description: Text(
                      tr("保存后，开启“按裁边与分格阅读”查看效果。",
                          "Save, then enable cropped and panel reading to apply it."),
                      style: Theme.of(context).textTheme.bodySmall))),
          OverflowBar(alignment: MainAxisAlignment.end, children: [
            TextButton(
                onPressed: _saving || _detecting
                    ? null
                    : () => _change(const DocumentPageLayout()),
                child: Text(tr('重置', 'Reset'))),
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(tr('取消', 'Cancel'))),
            FilledButton(
                onPressed:
                    _saving || _busy || _failed || _detecting ? null : _save,
                child: Text(
                    _saving ? tr('保存中…', 'Saving…') : tr('确定', 'Confirm'))),
          ]),
          const SizedBox(height: 8),
        ]),
      )));
}

class DocumentCropPainter extends CustomPainter {
  const DocumentCropPainter(this.layout, this.color, {this.fontFamily});
  final DocumentPageLayout layout;
  final Color color;
  final String? fontFamily;
  @override
  void paint(Canvas canvas, Size size) {
    Rect pixels(Rect r) => Rect.fromLTWH(r.left * size.width,
        r.top * size.height, r.width * size.width, r.height * size.height);
    final crop = pixels(layout.crop);
    canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRect(crop),
        Paint()..color = Colors.black.withValues(alpha: .4));
    final regions = layout.regions;
    for (var i = 0; i < regions.length; i++) {
      final rect = pixels(regions[i]);
      canvas.drawRect(
          rect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      final label = TextPainter(
          text: TextSpan(
              text: '${i + 1}',
              style: TextStyle(
                  fontFamily: fontFamily,
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr)
        ..layout();
      canvas.drawCircle(rect.center, 13, Paint()..color = color);
      label.paint(
          canvas, rect.center - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(DocumentCropPainter old) =>
      old.layout != layout ||
      old.color != color ||
      old.fontFamily != fontFamily;
}
