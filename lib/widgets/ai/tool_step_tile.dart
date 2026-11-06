import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/tool_tile_base.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ToolStepTile extends StatefulWidget {
  const ToolStepTile({
    super.key,
    required this.step,
  });

  final ParsedToolStep step;

  @override
  State<ToolStepTile> createState() => _ToolStepTileState();
}

class _ToolStepTileState extends State<ToolStepTile> {
  @override
  Widget build(BuildContext context) {
    final statusColor = ToolTileBase.statusColorFor(widget.step.status);
    final toolName = AiToolRegistry.current.displayNameForId(
      widget.step.name,
      l10n: L10n.of(context),
    );

    return ToolTileBase(
      title: toolName,
      leadingIcon: Icons.build,
      statusColor: statusColor,
      contentBuilder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.step.input != null)
            _ExpandableField(
              label: 'Input',
              value: widget.step.input!,
            ),
          if (widget.step.output != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _ExpandableField(
                label: 'Output',
                value: widget.step.output!,
              ),
            ),
          if (widget.step.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _ExpandableField(
                label: 'Error',
                value: widget.step.error!,
              ),
            ),
        ],
      ),
    );
  }
}

class _ExpandableField extends StatelessWidget {
  const _ExpandableField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.labelMedium)),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 12),
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            ),
          ],
        ),
        FilledContainer(
          color: theme.colorScheme.primaryContainer,
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          radius: 6,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}
