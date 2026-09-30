import 'package:anx_reader/l10n/modu_strings.dart';
import 'dart:math' as math;

import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:anx_reader/widgets/context_menu/selection_toolbar_labels.dart';
import 'package:anx_reader/widgets/icon_and_text.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Compact primary actions plus a native overflow menu. Both use the same IDs
/// and callbacks, so hiding/reordering never changes an action's behaviour.
class SelectionActionToolbar extends StatefulWidget {
  const SelectionActionToolbar(
      {super.key,
      required this.items,
      required this.visibleCount,
      required this.axis,
      required this.maxExtent,
      required this.onAction,
      required this.onSettings,
      this.parentRoute});
  final List<SelectionToolbarItem> items;
  final int visibleCount;
  final Axis axis;
  final double maxExtent;
  final ValueChanged<SelectionToolbarItem> onAction;
  final VoidCallback onSettings;
  final ModalRoute<dynamic>? parentRoute;

  @override
  State<SelectionActionToolbar> createState() => _SelectionActionToolbarState();
}

class _SelectionActionToolbarState extends State<SelectionActionToolbar> {
  final MenuController _menuController = MenuController();
  final FocusNode _moreFocusNode = FocusNode();
  LocalHistoryEntry? _backEntry;

  void _handleMenuOpen() {
    // The reader toolbar is a standalone OverlayEntry, outside the route's
    // widget subtree. Register with its owning route so Android Back closes
    // only this menu, rather than leaving the book.
    final route = widget.parentRoute ?? ModalRoute.of(context);
    if (route == null) return;
    late final LocalHistoryEntry entry;
    entry = LocalHistoryEntry(onRemove: () {
      if (_backEntry != entry) return;
      _backEntry = null;
      _menuController.close();
    });
    _backEntry = entry;
    route.addLocalHistoryEntry(entry);
  }

  void _removeBackHandler() {
    final entry = _backEntry;
    _backEntry = null;
    entry?.remove();
  }

  @override
  void dispose() {
    _removeBackHandler();
    _moreFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = DefaultTextStyle.of(context).style;
    final labelHeight =
        MediaQuery.textScalerOf(context).scale(textStyle.fontSize ?? 14) *
            (textStyle.height ?? 1.4);
    final itemHeight = math.max(50.0, 26 + labelHeight);
    final itemExtent = widget.axis == Axis.horizontal ? 42 : itemHeight;
    final capacity =
        math.max(0, ((widget.maxExtent - 80) / itemExtent).floor());
    final count =
        math.min(widget.items.length, math.min(widget.visibleCount, capacity));
    return AxisFlex(
        axis: widget.axis,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in widget.items.take(count))
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: IconAndText(
                  key: ValueKey('selection-action-${item.id}'),
                  compact: true,
                  flexibleHeight: true,
                  icon: Icon(selectionToolbarIcon(item)),
                  text: selectionToolbarLabel(context, item),
                  onTap: () => widget.onAction(item)),
            ),
          if (widget.items.length > count)
            // MenuAnchor paints its portal above this toolbar's OverlayEntry.
            // A PopupMenu route is inserted below the reader's standalone entry,
            // allowing annotation controls to cover it and steal menu taps.
            MenuAnchor(
              controller: _menuController,
              childFocusNode: _moreFocusNode,
              useRootOverlay: true,
              consumeOutsideTap: true,
              onOpen: _handleMenuOpen,
              onClose: _removeBackHandler,
              style: const MenuStyle(
                  maximumSize:
                      WidgetStatePropertyAll(Size(300, double.infinity))),
              menuChildren: [
                for (final item in widget.items.skip(count))
                  PointerInterceptor(
                    child: MenuItemButton(
                      key: ValueKey('selection-overflow-${item.id}'),
                      leadingIcon: Icon(selectionToolbarIcon(item)),
                      onPressed: () => widget.onAction(item),
                      child: Text(selectionToolbarLabel(context, item)),
                    ),
                  ),
              ],
              builder: (context, controller, _) => IconButton(
                key: const ValueKey('selection-toolbar-more'),
                focusNode: _moreFocusNode,
                tooltip: ModuStrings.text(context, '更多操作', 'More actions'),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_horiz),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          IconButton(
              key: const ValueKey('selection-toolbar-settings'),
              tooltip: ModuStrings.text(context, '划词工具栏设置', 'Selection toolbar settings'),
              constraints: const BoxConstraints.tightFor(width: 32, height: 40),
              padding: const EdgeInsets.all(4),
              icon: const Icon(Icons.tune, size: 20),
              onPressed: widget.onSettings),
        ]);
  }
}
