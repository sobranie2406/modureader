import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:anx_reader/service/ai/mindmap_export.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/tool_tile_base.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:graphview/GraphView.dart';

class MindmapStepTile extends StatefulWidget {
  const MindmapStepTile({
    super.key,
    required this.step,
    this.saveExport,
  });

  final ParsedToolStep step;
  final Future<String?> Function(Uint8List bytes, String name, String mimeType)?
      saveExport;

  @override
  State<MindmapStepTile> createState() => _MindmapStepTileState();
}

class _MindmapStepTileState extends State<MindmapStepTile> {
  MindmapPayload? _payload;
  String? _error;
  MindmapExportDocument? _document;
  bool _exporting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshBundle();
  }

  @override
  void didUpdateWidget(covariant MindmapStepTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step.output != oldWidget.step.output) {
      _refreshBundle();
    }
  }

  void _refreshBundle() {
    final output = widget.step.output;
    if (output == null || output.trim().isEmpty) {
      setState(() {
        _payload = null;
        _document = null;
        _error = L10n.of(context).mindmapWaitingForOutput;
      });
      return;
    }

    try {
      final decoded = jsonDecode(output);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Tool output is not a JSON object');
      }

      final status = decoded['status'];
      if (status != 'ok') {
        final message =
            decoded['message']?.toString() ?? L10n.of(context).mindmapToolError;
        throw FormatException(message);
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Mindmap payload missing data object');
      }

      // Keep the complete root and regenerate unique IDs for malformed AI IDs.
      final document = MindmapExportDocument.fromJson(data);
      final payload = MindmapPayload.fromJson({
        ...data,
        'root': document.root.toJson(),
      }, context);
      setState(() {
        _document = document;
        _payload = payload;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _payload = null;
        _document = null;
        _error = L10n.of(context).mindmapParseFailed(error.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = ToolTileBase.statusColorFor(widget.step.status);

    return ToolTileBase(
      title: widget.step.name,
      leadingIcon: Icons.account_tree,
      statusColor: statusColor,
      initiallyExpanded: true,
      contentBuilder: (context) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null) {
      return Text(_error!, style: theme.textTheme.bodyMedium);
    }

    final payload = _payload;
    if (payload == null) {
      return Text(L10n.of(context).mindmapGenerating,
          style: theme.textTheme.bodyMedium);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<MindmapExportFormat>(
            key: const ValueKey('mindmap-export'),
            enabled: !_exporting && _document != null,
            tooltip: Localizations.localeOf(context).languageCode == 'zh'
                ? '导出思维导图'
                : 'Export mind map',
            onSelected: _export,
            itemBuilder: (_) => MindmapExportFormat.values
                .map((format) => PopupMenuItem(
                      value: format,
                      child: Text('${format.label} (.${format.extension})'),
                    ))
                .toList(),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_exporting)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  const Icon(Icons.file_download_outlined, size: 20),
                const SizedBox(width: 6),
                Text(Localizations.localeOf(context).languageCode == 'zh'
                    ? '导出'
                    : 'Export'),
              ]),
            ),
          ),
        ),
        FilledContainer(
          width: double.infinity,
          height: 420,
          radius: 12,
          child: MindmapViewer(payload: payload),
        ),
        if (payload.stats != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              L10n.of(context).mindmapStats(
                payload.stats!.depth,
                payload.stats!.nodeCount,
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Future<void> _export(MindmapExportFormat format) async {
    final document = _document;
    if (_exporting || document == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    setState(() => _exporting = true);
    try {
      final bytes = await document.export(format);
      if (!mounted) return;
      final name = document.fileName(format);
      final path = widget.saveExport != null
          ? await widget.saveExport!(bytes, name, format.mimeType)
          : await saveFileToDownload(
              bytes: bytes, fileName: name, mimeType: format.mimeType);
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(zh ? '导图已保存：$path' : 'Mind map saved: $path'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(zh
                ? '导出失败，请重试。大型导图可选择 SVG 或 Markdown。'
                : 'Export failed. Try again, or use SVG / Markdown for large maps.')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// A single gesture surface for both the chat preview and the full-screen map.
/// Each surface owns its graph: graphview mutates node positions during layout.
class MindmapViewer extends StatefulWidget {
  const MindmapViewer({
    super.key,
    required this.payload,
    this.fullscreen = false,
    this.initialCollapsed = const {},
    this.onCollapsedChanged,
  });

  final MindmapPayload payload;
  final bool fullscreen;
  final Set<String> initialCollapsed;
  final ValueChanged<Set<String>>? onCollapsedChanged;

  @override
  State<MindmapViewer> createState() => _MindmapViewerState();
}

class _MindmapViewerState extends State<MindmapViewer> {
  static const _minScale = 0.01;
  static const _maxScale = 5.0;
  final _transform = TransformationController();
  late Set<String> _collapsed;
  late MindmapGraphBundle _bundle;
  Size _viewportSize = Size.zero;
  bool _fitScheduled = false;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _collapsed = {...widget.initialCollapsed};
    _buildGraph();
  }

  @override
  void didUpdateWidget(covariant MindmapViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.payload, widget.payload)) {
      _collapsed = {...widget.initialCollapsed};
      _buildGraph();
      _scheduleFit();
    }
  }

  void _buildGraph() {
    _bundle = MindmapGraphBundle.fromPayload(widget.payload,
        collapsedIds: _collapsed);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _scheduleFit() {
    if (_fitScheduled) return;
    _fitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitScheduled = false;
      if (mounted) _fit();
    });
  }

  void _fit() {
    if (_viewportSize.isEmpty) return;
    final bounds = _bundle.graph.calculateGraphBounds();
    if (bounds.isEmpty) return;
    final scale = math
        .min(
          math.max(1, _viewportSize.width - 32) / bounds.width,
          math.max(1, _viewportSize.height - 32) / bounds.height,
        )
        .clamp(_minScale, 1.0);
    _transform.value = Matrix4.diagonal3Values(scale, scale, scale)
      ..setTranslationRaw(_viewportSize.width / 2 - bounds.center.dx * scale,
          _viewportSize.height / 2 - bounds.center.dy * scale, 0);
  }

  void _zoom(double factor) {
    final focal = _viewportSize.center(Offset.zero);
    final scene = _transform.toScene(focal);
    final scale = (_transform.value.getMaxScaleOnAxis() * factor)
        .clamp(_minScale, _maxScale);
    _transform.value = Matrix4.diagonal3Values(scale, scale, scale)
      ..setTranslationRaw(
          focal.dx - scene.dx * scale, focal.dy - scene.dy * scale, 0);
  }

  void _toggle(String id) {
    final before = _bundle.graph.nodes.firstWhere((n) => n.key?.value == id);
    final center =
        before.position + Offset(before.width / 2, before.height / 2);
    final screen = MatrixUtils.transformPoint(_transform.value, center);
    setState(() {
      if (!_collapsed.remove(id)) _collapsed.add(id);
      _buildGraph();
    });
    widget.onCollapsedChanged?.call({..._collapsed});
    final bundle = _bundle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(bundle, _bundle)) return;
      // Keep the tapped parent in place as its descendants change the layout.
      final after = bundle.graph.nodes.firstWhere((n) => n.key?.value == id);
      final center = after.position + Offset(after.width / 2, after.height / 2);
      final scale = _transform.value.getMaxScaleOnAxis();
      _transform.value = Matrix4.diagonal3Values(scale, scale, scale)
        ..setTranslationRaw(
            screen.dx - center.dx * scale, screen.dy - center.dy * scale, 0);
    });
  }

  void _setAll(bool collapse) {
    final ids = <String>{};
    void visit(MindmapNodeData node) {
      if (node.children.isNotEmpty) ids.add(node.id);
      for (final child in node.children) {
        visit(child);
      }
    }

    if (collapse) visit(widget.payload.root);
    setState(() {
      _collapsed = ids;
      _buildGraph();
    });
    widget.onCollapsedChanged?.call({..._collapsed});
    _scheduleFit();
  }

  Future<void> _openFullscreen() async {
    final payload = widget.payload;
    var collapsed = {..._collapsed};
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).maybePop(),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              key: const ValueKey('mindmap-fullscreen-page'),
              appBar: AppBar(
                title: Text(payload.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              body: SafeArea(
                child: MindmapViewer(
                  payload: payload,
                  fullscreen: true,
                  initialCollapsed: collapsed,
                  onCollapsedChanged: (value) => collapsed = value,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || !identical(payload, widget.payload)) return;
    setState(() {
      _collapsed = collapsed;
      _buildGraph();
    });
    _scheduleFit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Consume blank/leaf taps instead of collapsing the surrounding tool tile.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Column(
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('mindmap-zoom-out'),
                tooltip: _zh ? '缩小' : 'Zoom out',
                onPressed: () => _zoom(1 / 1.25),
                icon: const Icon(Icons.zoom_out),
              ),
              ValueListenableBuilder<Matrix4>(
                valueListenable: _transform,
                builder: (_, value, __) => SizedBox(
                  width: 48,
                  child: Text('${(value.getMaxScaleOnAxis() * 100).round()}%',
                      textAlign: TextAlign.center),
                ),
              ),
              IconButton(
                key: const ValueKey('mindmap-zoom-in'),
                tooltip: _zh ? '放大' : 'Zoom in',
                onPressed: () => _zoom(1.25),
                icon: const Icon(Icons.zoom_in),
              ),
              IconButton(
                key: const ValueKey('mindmap-fit'),
                tooltip: _zh ? '适应窗口' : 'Fit to window',
                onPressed: _fit,
                icon: const Icon(Icons.fit_screen),
              ),
              IconButton(
                key: const ValueKey('mindmap-expand-all'),
                tooltip: _zh ? '全部展开' : 'Expand all',
                onPressed: () => _setAll(false),
                icon: const Icon(Icons.unfold_more),
              ),
              IconButton(
                key: const ValueKey('mindmap-collapse-all'),
                tooltip: _zh ? '全部收起' : 'Collapse all',
                onPressed: () => _setAll(true),
                icon: const Icon(Icons.unfold_less),
              ),
              if (!widget.fullscreen)
                IconButton(
                  key: const ValueKey('mindmap-fullscreen'),
                  tooltip: _zh ? '全屏查看' : 'Full screen',
                  onPressed: _openFullscreen,
                  icon: const Icon(Icons.fullscreen),
                ),
            ],
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final size = constraints.biggest;
              if (_viewportSize != size) {
                _viewportSize = size;
                _scheduleFit();
              }
              return ClipRect(
                child: InteractiveViewer(
                  key: const ValueKey('mindmap-canvas'),
                  transformationController: _transform,
                  constrained: false,
                  alignment: Alignment.topLeft,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  minScale: _minScale,
                  maxScale: _maxScale,
                  child: GraphView(
                    key: ObjectKey(_bundle),
                    graph: _bundle.graph,
                    algorithm: _bundle.algorithm,
                    animated: false,
                    paint: Paint()
                      ..color = theme.colorScheme.onSurface
                      ..strokeWidth = 2
                      ..style = PaintingStyle.stroke,
                    builder: (node) {
                      final id = node.key!.value.toString();
                      final data = _bundle.lookup[id]!;
                      final style =
                          _resolveLevelStyle(theme, _bundle.levels[id] ?? 0);
                      return _MindmapNodeCard(
                        key: ValueKey('mindmap-node-$id'),
                        label: data.label,
                        childCount: data.children.length,
                        collapsed: _collapsed.contains(id),
                        onTap: data.children.isEmpty ? null : () => _toggle(id),
                        backgroundColor: style.background,
                        foregroundColor: style.foreground,
                      );
                    },
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _MindmapNodeCard extends StatelessWidget {
  const _MindmapNodeCard({
    super.key,
    required this.label,
    required this.childCount,
    required this.collapsed,
    required this.onTap,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final int childCount;
  final bool collapsed;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Semantics(
      button: onTap != null,
      expanded: onTap == null ? null : !collapsed,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: foregroundColor)),
              ),
              if (childCount > 0) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: collapsed
                      ? (zh
                          ? '展开 $childCount 个分支'
                          : 'Expand $childCount branches')
                      : (zh ? '收起分支' : 'Collapse branches'),
                  child: Icon(
                      collapsed
                          ? Icons.add_circle_outline
                          : Icons.remove_circle_outline,
                      size: 20,
                      color: foregroundColor),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _LevelStyle {
  const _LevelStyle({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

_LevelStyle _resolveLevelStyle(ThemeData theme, int level) {
  final base = HSVColor.fromColor(theme.colorScheme.primary);
  final hue = (base.hue + (level * 32)) % 360;
  final saturation = (0.35 + (level % 5) * 0.08).clamp(0.2, 0.85);
  final value = (0.9 - (level % 6) * 0.06).clamp(0.3, 0.95);
  final background = HSVColor.fromAHSV(1, hue, saturation, value).toColor();
  final foreground =
      background.computeLuminance() > 0.55 ? Colors.black : Colors.white;
  return _LevelStyle(background: background, foreground: foreground);
}

class MindmapGraphBundle {
  MindmapGraphBundle({
    required this.graph,
    required this.algorithm,
    required this.lookup,
    required this.stats,
    required this.levels,
  });

  factory MindmapGraphBundle.fromPayload(MindmapPayload payload,
      {Set<String> collapsedIds = const {}}) {
    final graph = Graph()..isTree = true;
    final lookup = <String, MindmapNodeData>{};
    final nodeCache = <String, Node>{};
    final levels = <String, int>{};

    Node ensureNode(MindmapNodeData data) {
      lookup[data.id] = data;
      return nodeCache.putIfAbsent(data.id, () => Node.Id(data.id));
    }

    void visit(MindmapNodeData node, int level) {
      final parentNode = ensureNode(node);
      graph.addNode(parentNode);
      levels[node.id] = level;
      if (collapsedIds.contains(node.id)) return;
      for (final child in node.children) {
        final childNode = ensureNode(child);
        graph.addEdge(parentNode, childNode);
        visit(child, level + 1);
      }
    }

    visit(payload.root, 0);

    final config = BuchheimWalkerConfiguration()
      ..siblingSeparation = 10
      ..levelSeparation = 200
      ..subtreeSeparation = 20
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_LEFT_RIGHT;

    final algorithm = _BoundedMindmapAlgorithm(
      config,
      MindmapEdgeRenderer(config),
    );

    return MindmapGraphBundle(
      graph: graph,
      algorithm: algorithm,
      lookup: lookup,
      stats: payload.stats,
      levels: levels,
    );
  }

  final Graph graph;
  final Algorithm algorithm;
  final Map<String, MindmapNodeData> lookup;
  final MindmapStats? stats;
  final Map<String, int> levels;
}

class _BoundedMindmapAlgorithm extends MindmapAlgorithm {
  _BoundedMindmapAlgorithm(super.config, super.renderer);

  @override
  Size run(Graph? graph, double shiftX, double shiftY) {
    super.run(graph, shiftX, shiftY);
    final bounds = graph!.calculateGraphBounds();
    // MindmapAlgorithm places left branches at negative coordinates, while
    // GraphView's RenderBox covers only 0..size. Painting outside that box works
    // but hit-testing does not. Normalize every node (and hence its edges).
    for (final node in graph.nodes) {
      node.position -= bounds.topLeft;
    }
    return bounds.size;
  }
}

class MindmapPayload {
  MindmapPayload({
    required this.title,
    required this.outline,
    required this.root,
    this.stats,
  });

  factory MindmapPayload.fromJson(
      Map<String, dynamic> json, BuildContext context) {
    final rootJson = json['root'];
    if (rootJson is! Map<String, dynamic>) {
      throw const FormatException('Mindmap payload is missing root node');
    }

    return MindmapPayload(
      title: json['title']?.toString() ?? L10n.of(context).mindmapDefaultTitle,
      outline: json['outline']?.toString() ?? '',
      root: MindmapNodeData.fromJson(rootJson, context),
      stats: json['stats'] is Map<String, dynamic>
          ? MindmapStats.fromJson(json['stats'] as Map<String, dynamic>)
          : null,
    );
  }

  final String title;
  final String outline;
  final MindmapNodeData root;
  final MindmapStats? stats;
}

class MindmapNodeData {
  MindmapNodeData({
    required this.id,
    required this.label,
    required this.children,
  });

  factory MindmapNodeData.fromJson(
      Map<String, dynamic> json, BuildContext context) {
    final children = (json['children'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((child) => MindmapNodeData.fromJson(child, context))
        .toList(growable: false);

    return MindmapNodeData(
      id: json['id']?.toString() ?? L10n.of(context).mindmapDefaultNodeId,
      label:
          json['label']?.toString() ?? L10n.of(context).mindmapDefaultNodeLabel,
      children: children,
    );
  }

  final String id;
  final String label;
  final List<MindmapNodeData> children;
}

class MindmapStats {
  MindmapStats({required this.nodeCount, required this.depth});

  factory MindmapStats.fromJson(Map<String, dynamic> json) {
    return MindmapStats(
      nodeCount: int.tryParse(json['nodeCount']?.toString() ?? '') ?? 0,
      depth: int.tryParse(json['depth']?.toString() ?? '') ?? 0,
    );
  }

  final int nodeCount;
  final int depth;
}
