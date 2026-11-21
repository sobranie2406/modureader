import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/enums/page_turn_mode.dart';
import 'package:modu_reader/enums/page_turning_type.dart';

List<PageTurningType> type1 = [
  PageTurningType.prev,
  PageTurningType.menu,
  PageTurningType.next,
  PageTurningType.prev,
  PageTurningType.menu,
  PageTurningType.next,
  PageTurningType.prev,
  PageTurningType.menu,
  PageTurningType.next
];
List<int> icon1 = [5, 3, 4];

List<PageTurningType> type2 = [
  PageTurningType.prev,
  PageTurningType.prev,
  PageTurningType.next,
  PageTurningType.prev,
  PageTurningType.menu,
  PageTurningType.next,
  PageTurningType.prev,
  PageTurningType.next,
  PageTurningType.next
];
List<int> icon2 = [5, 3, 4];

List<PageTurningType> type3 = [
  PageTurningType.prev,
  PageTurningType.prev,
  PageTurningType.next,
  PageTurningType.prev,
  PageTurningType.menu,
  PageTurningType.next,
  PageTurningType.next,
  PageTurningType.next,
  PageTurningType.next
];
List<int> icon3 = [5, 3, 4];

List<PageTurningType> type4 = [
  PageTurningType.menu,
  PageTurningType.menu,
  PageTurningType.menu,
  PageTurningType.prev,
  PageTurningType.next,
  PageTurningType.next,
  PageTurningType.prev,
  PageTurningType.next,
  PageTurningType.next
];
// next, prev, menu
List<int> icon4 = [5, 3, 1];

List<PageTurningType> type5 = [
  PageTurningType.next,
  PageTurningType.menu,
  PageTurningType.next,
  PageTurningType.next,
  PageTurningType.prev,
  PageTurningType.next,
  PageTurningType.next,
  PageTurningType.next,
  PageTurningType.next
];
// next, prev, menu from 0
List<int> icon5 = [7, 4, 1];

List<List<PageTurningType>> pageTurningTypes = [
  type1,
  type2,
  type3,
  type4,
  type5
];
List<List<int>> pageTurningIcons = [icon1, icon2, icon3, icon4, icon5];

PageTurningType readerTapAction(int region) {
  final prefs = Prefs();
  final mode = PageTurnMode.fromCode(prefs.pageTurnMode);
  final preset = prefs.pageTurningType.clamp(0, pageTurningTypes.length - 1);
  final action = mode == PageTurnMode.custom
      ? PageTurningType.values[prefs.customPageTurnConfig[region]]
      : pageTurningTypes[preset][region];

  if (action != PageTurningType.prev && action != PageTurningType.next) {
    return action;
  }
  if (prefs.keyboardShortcutTurnPage) return PageTurningType.none;
  if (mode == PageTurnMode.simple && prefs.swapPageTurnArea) {
    return action == PageTurningType.prev
        ? PageTurningType.next
        : PageTurningType.prev;
  }
  return action;
}
