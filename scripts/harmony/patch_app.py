"""Adapt audited newer Flutter APIs in the disposable Flutter OH checkout.

Flutter OH 3.41.9 uses onReorder (destination before source removal), whereas
Modu's normal Flutter uses onReorderItem (destination after source removal).
Do not rename blindly: downward moves need the one-slot adjustment. Remove
this adapter after an audited Flutter OH upgrade supports onReorderItem.

Flutter OH also lacks Hero.curve/reverseCurve. Omit those arguments in this
temporary checkout while retaining the shared cover transition and gestures.

The three Cupertino sheet callbacks do not consume the newer controller;
adapt them to the older builder API in the OHOS checkout only.
"""
import os
from pathlib import Path
import sys

PATCHES = {
    'lib/widgets/home_navigation_shell.dart': (
        'scrollableBuilder: (BuildContext context, ScrollController controller) {',
        'builder: (BuildContext context) {'),
    'lib/service/initialization_check.dart': (
        'scrollableBuilder: (sheetContext, controller) => ChangelogScreen(\n'
        '          lastVersion: previous,\n'
        '          currentVersion: current,\n'
        '          onComplete: () => Navigator.pop(sheetContext),\n'
        '        ),',
        'builder: (sheetContext) => ChangelogScreen(\n'
        '          lastVersion: previous,\n'
        '          currentVersion: current,\n'
        '          onComplete: () => Navigator.pop(sheetContext),\n'
        '        ),'),
    'lib/page/settings_page/advanced.dart': (
        'scrollableBuilder: (BuildContext context, ScrollController controller) {',
        'builder: (BuildContext context) {'),
    'lib/page/settings_page/ai_reading_skills.dart': (
        'onReorderItem: (oldIndex, newIndex) {',
        'onReorder: (oldIndex, newIndex) {\n'
        '        if (newIndex > oldIndex) newIndex -= 1;'),
    'lib/page/settings_page/selection_toolbar.dart': (
        'onReorderItem: (a, b) => _reorder(a, b, annotations, items),',
        'onReorder: (a, b) => _reorder(a, b > a ? b - 1 : b, annotations, items),'),
    'lib/widgets/dictionary/unified_query_settings.dart': (
        'onReorderItem: (oldIndex, newIndex) {',
        'onReorder: (oldIndex, newIndex) {\n'
        '                if (newIndex > oldIndex) newIndex -= 1;'),
    'lib/widgets/reading_page/reader_top_actions.dart': (
        'onReorderItem: (oldIndex, newIndex) {',
        'onReorder: (oldIndex, newIndex) {\n'
        '              if (newIndex > oldIndex) newIndex -= 1;'),
    'lib/widgets/page_router/reader_cover_hero.dart': (
        '          tag: tag,\n'
        '          transitionOnUserGestures: true,\n'
        '          curve: Curves.linear,\n'
        '          reverseCurve: Curves.linear,',
        '          tag: tag, // OHOS SDK lacks Hero curve arguments.\n'
        '          transitionOnUserGestures: true,'),
}

ANCHOR_COUNTS = {
    'lib/service/initialization_check.dart': 1,
    'lib/page/settings_page/advanced.dart': 1,
}


def plan(root):
    result = {}
    for relative, (before, after) in PATCHES.items():
        path = root / relative
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('App source must remain inside the checkout')
        text = path.read_text()
        count = ANCHOR_COUNTS.get(relative, 1)
        if text.count(before) != count:
            raise ValueError(f'{relative}: expected {count} reviewed API anchors; re-audit required')
        if 'onReorderItem:' in before and text.count('onReorderItem:') != 1:
            raise ValueError(f'{relative}: expected one reviewed reorder callback; re-audit required')
        result[path] = text.replace(before, after)
    return result


def install(root):
    root = root.resolve()
    if (sys.platform != 'linux' or os.environ.get('GITHUB_ACTIONS') != 'true'
            or not os.environ.get('GITHUB_WORKSPACE')
            or Path(os.environ['GITHUB_WORKSPACE']).resolve() != root):
        raise ValueError('Run only in the Linux GitHub Actions temporary checkout')
    edits = plan(root)
    originals = {path: path.read_bytes() for path in edits}
    try:
        for path, text in edits.items():
            path.write_text(text)
    except BaseException:
        for path, data in originals.items():
            path.write_bytes(data)
        raise
    print('Adapted reorder, Hero and Cupertino sheet APIs; canonical source unchanged.')


if __name__ == '__main__':
    try:
        install(Path.cwd())
    except (OSError, ValueError) as error:
        sys.exit(str(error))
