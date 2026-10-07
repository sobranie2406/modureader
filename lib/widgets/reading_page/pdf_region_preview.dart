import 'package:anx_reader/utils/app_motion.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/document_page_layout.dart';
import 'package:anx_reader/widgets/reading_page/document_layout_editor.dart';
import 'package:anx_reader/models/document_enhancement.dart';
import 'package:anx_reader/widgets/reading_page/document_enhancement_panel.dart';
import 'package:flutter/material.dart';

/// Original-page/region preview, separate from the main reader's position and
/// annotations. Layouts are saved only through explicit editor confirmation.
class PdfRegionPreview extends StatefulWidget {
  const PdfRegionPreview({
    super.key,
    required this.info,
    required this.render,
    required this.cancelRender,
    required this.close,
    this.initialLayout = const DocumentLayoutConfig(),
    this.saveLayout,
    this.startWithLayoutEditor = false,
    this.imageEpub = false,
    this.initialEnhancement = const DocumentEnhancement(),
    this.saveEnhancement,
  }) : assert(!startWithLayoutEditor || saveLayout != null);

  final Future<Map<String, dynamic>> Function(int? page) info;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) render;
  final VoidCallback cancelRender;
  final VoidCallback close;
  final DocumentLayoutConfig initialLayout;
  final Future<void> Function(DocumentLayoutConfig)? saveLayout;

  /// Open the editor in this route, without a preview route underneath it.
  final bool startWithLayoutEditor;
  final bool imageEpub;
  final DocumentEnhancement initialEnhancement;
  final Future<void> Function(DocumentEnhancement)? saveEnhancement;

  @override
  State<PdfRegionPreview> createState() => _PdfRegionPreviewState();
}

class _PdfRegionPreviewState extends State<PdfRegionPreview> {
  int _page = 0, _total = 0, _rotation = 0, _generation = 0;
  double _aspect = 1, _zoom = 1;
  Offset _center = const Offset(.5, .5);
  Size _viewSize = Size.zero;
  Uint8List? _bytes;
  bool _loadingPage = true, _busy = true, _failed = false;
  Timer? _timer;
  ImageProvider? _displayedImage;
  late DocumentLayoutConfig _layout;
  int _regionIndex = 0;
  bool _original = false, _editing = false;
  int? _requestedPage;
  bool _requestedLastRegion = false;
  bool _unsupported = false;
  late DocumentEnhancement _enhancement = widget.initialEnhancement;

  List<Rect> get _regions => _original
      ? const [Rect.fromLTWH(0, 0, 1, 1)]
      : _layout.forPage(_page).regions;
  Rect get _sourceRegion =>
      _regions[_regionIndex.clamp(0, _regions.length - 1)];
  Rect get _rotatedRegion => rotateDocumentRegion(_sourceRegion, _rotation);

  @override
  void initState() {
    super.initState();
    _layout = widget.initialLayout;
    _loadPage(null);
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    widget.close();
    // Preview images are large and transient, not part of the shared book cache.
    _displayedImage?.evict();
    super.dispose();
  }

  Future<void> _loadPage(int? page, {bool lastRegion = false}) async {
    _requestedPage = page;
    _requestedLastRegion = lastRegion;
    final generation = ++_generation;
    _timer?.cancel();
    widget.cancelRender();
    setState(() {
      _loadingPage = true;
      _busy = true;
      _failed = false;
      _unsupported = false;
      _bytes = null;
    });
    try {
      final result = await widget.info(page);
      if (!mounted || generation != _generation) return;
      final width = (result['width'] as num).toDouble();
      final height = (result['height'] as num).toDouble();
      final total = (result['total'] as num).toInt();
      final index = (result['page'] as num).toInt();
      if (!width.isFinite ||
          !height.isFinite ||
          width <= 0 ||
          height <= 0 ||
          total <= 0 ||
          index < 0 ||
          index >= total) {
        throw const FormatException('Invalid PDF dimensions');
      }
      setState(() {
        _page = index;
        _regionIndex = lastRegion ? _regions.length - 1 : 0;
        _total = total;
        _aspect = width / height;
        _rotation = 0;
        _zoom = 1;
        _center = const Offset(.5, .5);
        _loadingPage = false;
        _unsupported = result['imageOnly'] == false;
        if (_unsupported) _busy = false;
      });
      _scheduleRender();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  Size get _imageSize {
    final regionAspect = _aspect * _sourceRegion.width / _sourceRegion.height;
    final aspect = _rotation % 180 == 0 ? regionAspect : 1 / regionAspect;
    final width = math.min(_viewSize.width, _viewSize.height * aspect);
    return Size(width, width / aspect);
  }

  void _scheduleRender() {
    if (_editing || widget.startWithLayoutEditor) return;
    _timer?.cancel();
    final generation = ++_generation;
    widget.cancelRender();
    if (_loadingPage || _unsupported || _viewSize.isEmpty) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    // Coalesce slider/drag/resize events; obsolete bridge replies are ignored.
    _timer = Timer(const Duration(milliseconds: 90), () => _render(generation));
  }

  Future<void> _render(int generation) async {
    if (!mounted || generation != _generation) return;
    final size = _imageSize;
    final edge = 1 / _zoom;
    final crop = _rotatedRegion;
    final dpr = math.min(2.0, MediaQuery.devicePixelRatioOf(context));
    try {
      final result = await widget.render({
        'page': _page,
        'enhancement':
            (_original ? const DocumentEnhancement() : _enhancement).toJson(),
        'rotation': _rotation,
        'region': {
          'x': math.max(0.0, crop.left + (_center.dx - edge / 2) * crop.width),
          'y': math.max(0.0, crop.top + (_center.dy - edge / 2) * crop.height),
          'width': edge * crop.width,
          'height': edge * crop.height
        },
        'width': math.max(1, (size.width * dpr).round()),
        'height': math.max(1, (size.height * dpr).round()),
      });
      if (!mounted || generation != _generation) return;
      final data = result['dataUrl'] as String;
      if (!data.startsWith('data:image/png;base64,')) {
        throw const FormatException('Invalid PDF preview image');
      }
      final bytes =
          base64Decode(data.substring('data:image/png;base64,'.length));
      final previous = _displayedImage;
      setState(() {
        _bytes = bytes;
        _displayedImage = MemoryImage(bytes);
        _busy = false;
      });
      previous?.evict();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  void _setZoom(double value) {
    final zoom = value.clamp(1.0, 15.0);
    final half = .5 / zoom;
    setState(() {
      _zoom = zoom;
      _center = Offset(
          _center.dx.clamp(half, 1 - half), _center.dy.clamp(half, 1 - half));
    });
    _scheduleRender();
  }

  void _pan(DragUpdateDetails details) {
    if (_zoom == 1 || _loadingPage || _imageSize.isEmpty) return;
    final size = _imageSize, half = .5 / _zoom;
    setState(() {
      _center = Offset(
          (_center.dx - details.delta.dx / size.width / _zoom)
              .clamp(half, 1 - half),
          (_center.dy - details.delta.dy / size.height / _zoom)
              .clamp(half, 1 - half));
    });
    _scheduleRender();
  }

  void _rotate() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
      _center = const Offset(.5, .5);
      _zoom = 1;
      _bytes = null;
    });
    _scheduleRender();
  }

  void _changeRegion(int delta) {
    final next = _regionIndex + delta;
    if (next < 0) {
      if (_page > 0) _loadPage(_page - 1, lastRegion: true);
    } else if (next >= _regions.length) {
      if (_page + 1 < _total) _loadPage(_page + 1);
    } else {
      setState(() {
        _regionIndex = next;
        _zoom = 1;
        _center = const Offset(.5, .5);
        _bytes = null;
      });
      _scheduleRender();
    }
  }

  Future<void> _editLayout() async {
    if (_editing || _loadingPage || _unsupported || widget.saveLayout == null) {
      return;
    }
    _editing = true;
    _generation++;
    _timer?.cancel();
    widget.cancelRender();
    final result = await showDialog<DocumentLayoutConfig>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (_) => DocumentLayoutEditor(
            initial: _layout,
            page: _page,
            total: _total,
            info: widget.info,
            render: widget.render,
            cancelRender: widget.cancelRender,
            save: widget.saveLayout!));
    if (!mounted) return;
    setState(() {
      _editing = false;
      if (result != null) {
        _layout = result;
        _original = false;
        _regionIndex = 0;
        _rotation = 0;
        _zoom = 1;
        _center = const Offset(.5, .5);
        _bytes = null;
      }
    });
    _scheduleRender();
  }

  @override
  Widget build(BuildContext context) {
    String tr(String zh, String en) => ModuStrings.text(context, zh, en);
    if (widget.startWithLayoutEditor) {
      if (!_loadingPage && !_failed && !_unsupported) {
        return DocumentLayoutEditor(
            initial: _layout,
            page: _page,
            total: _total,
            info: widget.info,
            render: widget.render,
            cancelRender: widget.cancelRender,
            save: widget.saveLayout!);
      }
      // Resolve the current original page first; no intermediate preview render
      // or additional navigation is needed. Loading is cancellable/retryable.
      return Dialog.fullscreen(
          child: SafeArea(
              child: Column(children: [
        Row(children: [
          IconButton(
              tooltip: tr('关闭', 'Close'),
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context)),
          Expanded(
              child: Text(tr('裁边与分格', 'Crop and panels'),
                  style: Theme.of(context).textTheme.titleLarge)),
        ]),
        Expanded(
            child: Center(
                child: _failed || _unsupported
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_unsupported
                            ? tr('本页包含文字或暂不支持的图片排版，请返回原文或选择其他页。',
                                'This page contains text or an unsupported image layout. Return to the original reader or select another page.')
                            : tr('预览失败，原文件未改动。',
                                'Preview failed. The source is unchanged.')),
                        TextButton(
                            onPressed: () => _loadPage(_requestedPage),
                            child: Text(tr('重试', 'Retry'))),
                        if (_unsupported)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                tooltip: tr('上一原页', 'Previous original page'),
                                onPressed: _page > 0
                                    ? () => _loadPage(_page - 1)
                                    : null,
                                icon: const Icon(Icons.chevron_left)),
                            Text('${_page + 1} / $_total'),
                            IconButton(
                                tooltip: tr('下一原页', 'Next original page'),
                                onPressed: _page + 1 < _total
                                    ? () => _loadPage(_page + 1)
                                    : null,
                                icon: const Icon(Icons.chevron_right)),
                          ]),
                      ])
                    : const EinkStaticIndicator(
                        child: CircularProgressIndicator()))),
      ])));
    }
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(children: [
          Row(children: [
            IconButton(
                tooltip: tr('关闭', 'Close'),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
            Expanded(
                child: Text(
                    widget.imageEpub
                        ? tr('扫描图片原图', 'Scanned image pages')
                        : tr('PDF 局部预览', 'PDF region preview'),
                    style: Theme.of(context).textTheme.titleMedium)),
            if (widget.saveLayout != null)
              IconButton(
                  tooltip: tr('裁边与分格', 'Crop and panels'),
                  icon: const Icon(Icons.crop),
                  onPressed: _loadingPage || _unsupported ? null : _editLayout),
            if (widget.saveEnhancement != null)
              IconButton(
                  tooltip: tr('图像增强', 'Image enhancement'),
                  icon: const Icon(Icons.tune),
                  onPressed: _loadingPage || _unsupported
                      ? null
                      : () async {
                          _editing = true;
                          _timer?.cancel();
                          _generation++;
                          widget.cancelRender();
                          final result = await showDialog<DocumentEnhancement>(
                              animationStyle: AppMotion.style,
                              context: context,
                              builder: (_) => DocumentEnhancementPanel(
                                  initial: _enhancement,
                                  render: (request) => widget
                                      .render({...request, 'page': _page}),
                                  cancelRender: widget.cancelRender,
                                  save: widget.saveEnhancement!));
                          if (!mounted) return;
                          setState(() {
                            _editing = false;
                            if (result != null) _enhancement = result;
                          });
                          _scheduleRender();
                        }),
            IconButton(
                tooltip: tr('向右旋转', 'Rotate right'),
                icon: const Icon(Icons.rotate_right),
                onPressed: _loadingPage ? null : _rotate),
            IconButton(
                tooltip: tr('恢复原图', 'Reset view'),
                icon: const Icon(Icons.restart_alt),
                onPressed: _loadingPage
                    ? null
                    : () {
                        setState(() {
                          _rotation = 0;
                          _center = const Offset(.5, .5);
                        });
                        _setZoom(1);
                      }),
          ]),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                  tr('临时预览：放大后拖动查看，不改变阅读进度、原文件或批注。',
                      'Temporary preview: zoom and drag. Reading position, source and annotations stay unchanged.'),
                  style: Theme.of(context).textTheme.bodySmall)),
          if (widget.saveLayout != null)
            Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                    icon: Icon(_original ? Icons.grid_view : Icons.compare),
                    label: Text(_original
                        ? tr('应用已存版式', 'Apply saved layout')
                        : tr('对照原图', 'Compare original')),
                    onPressed: _loadingPage
                        ? null
                        : () {
                            setState(() {
                              _original = !_original;
                              _regionIndex = 0;
                              _zoom = 1;
                              _center = const Offset(.5, .5);
                              _bytes = null;
                            });
                            _scheduleRender();
                          })),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            final size = constraints.biggest;
            if (size != _viewSize && !size.isEmpty) {
              _viewSize = size;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_loadingPage) _scheduleRender();
              });
            }
            return GestureDetector(
              key: const ValueKey('pdf-region-viewport'),
              behavior: HitTestBehavior.opaque,
              onPanUpdate: _pan,
              child: Stack(fit: StackFit.expand, children: [
                ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerLow),
                if (_bytes != null)
                  Center(
                      child: Image(
                          image: _displayedImage!,
                          fit: BoxFit.contain,
                          width: _imageSize.width,
                          height: _imageSize.height,
                          excludeFromSemantics: true,
                          errorBuilder: (_, __, ___) => Text(tr('图像解码失败，请重试。',
                              'Image decoding failed. Please retry.')))),
                if (_busy)
                  const Align(
                      alignment: Alignment.topCenter,
                      child: EinkStaticIndicator(
                          child: LinearProgressIndicator())),
                if (_unsupported)
                  Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                              tr('此章节含文字或不是可识别的纯图片页。请关闭此界面返回原正文，或使用下方按钮查看其他章节；没有删除或跳过正文。',
                                  'This section contains text or is not a supported image-only page. Close to read the original, or browse another section below. No content has been removed.'),
                              textAlign: TextAlign.center))),
                if (_failed)
                  Center(
                      child: Card(
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(tr('预览失败，原文件未改动。',
                                        'Preview failed. The source is unchanged.')),
                                    TextButton(
                                        onPressed: () => _loadingPage
                                            ? _loadPage(_requestedPage,
                                                lastRegion:
                                                    _requestedLastRegion)
                                            : _scheduleRender(),
                                        child: Text(tr('重试', 'Retry'))),
                                  ])))),
              ]),
            );
          })),
          Row(children: [
            IconButton(
                tooltip: tr('缩小', 'Zoom out'),
                onPressed: _loadingPage || _zoom <= 1
                    ? null
                    : () => _setZoom(_zoom - .5),
                icon: const Icon(Icons.remove)),
            Expanded(
                child: Slider(
                    value: _zoom,
                    min: 1,
                    max: 15,
                    divisions: 140,
                    label: '${(_zoom * 100).round()}%',
                    onChanged: _loadingPage ? null : _setZoom)),
            Text('${(_zoom * 100).round()}%'),
            IconButton(
                tooltip: tr('放大', 'Zoom in'),
                onPressed: _loadingPage || _zoom >= 15
                    ? null
                    : () => _setZoom(_zoom + .5),
                icon: const Icon(Icons.add)),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                tooltip: tr('上一原页', 'Previous original page'),
                onPressed: _loadingPage || _page <= 0
                    ? null
                    : () => _loadPage(_page - 1),
                icon: const Icon(Icons.chevron_left)),
            if (widget.saveLayout != null)
              IconButton(
                  tooltip: tr('上一区域', 'Previous region'),
                  icon: const Icon(Icons.navigate_before),
                  onPressed: _loadingPage || (_page == 0 && _regionIndex == 0)
                      ? null
                      : () => _changeRegion(-1)),
            Flexible(
                child: Text(
                    _total == 0
                        ? '—'
                        : '${_page + 1} / $_total'
                            '${_regions.length > 1 ? '\n${tr('区域', 'Region')} ${_regionIndex + 1} / ${_regions.length}' : ''}',
                    textAlign: TextAlign.center)),
            if (widget.saveLayout != null)
              IconButton(
                  tooltip: tr('下一区域', 'Next region'),
                  icon: const Icon(Icons.navigate_next),
                  onPressed: _loadingPage ||
                          (_page + 1 >= _total &&
                              _regionIndex + 1 >= _regions.length)
                      ? null
                      : () => _changeRegion(1)),
            IconButton(
                tooltip: tr('下一原页', 'Next original page'),
                onPressed: _loadingPage || _page + 1 >= _total
                    ? null
                    : () => _loadPage(_page + 1),
                icon: const Icon(Icons.chevron_right)),
          ]),
        ]),
      ),
    );
  }
}
