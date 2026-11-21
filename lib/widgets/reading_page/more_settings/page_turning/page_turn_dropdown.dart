import 'package:modu_reader/enums/page_turning_type.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/widgets/common/anx_dropdown_button.dart';
import 'package:flutter/material.dart';

class PageTurnDropdown extends StatelessWidget {
  const PageTurnDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PageTurningType value;
  final ValueChanged<PageTurningType?> onChanged;

  String _getLabel(BuildContext context, PageTurningType type) {
    switch (type) {
      case PageTurningType.none:
        return L10n.of(context).pageTurnActionNone;
      case PageTurningType.prev:
        return L10n.of(context).pageTurnActionPrev;
      case PageTurningType.next:
        return L10n.of(context).pageTurnActionNext;
      case PageTurningType.menu:
        return L10n.of(context).pageTurnActionMenu;
      case PageTurningType.contents:
        return ModuStrings.text(context, '打开目录', 'Open contents');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnxDropdownButton<PageTurningType>(
      value: value,
      items: PageTurningType.values
          .map((type) => DropdownItem<PageTurningType>(
                value: type,
                label: _getLabel(context, type),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
