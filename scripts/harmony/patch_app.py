"""Adapt two newer reorder callbacks in the disposable Flutter OH checkout.

Flutter OH 3.41.9 uses onReorder (destination before source removal), whereas
Modu's normal Flutter uses onReorderItem (destination after source removal).
Do not rename blindly: downward moves need the one-slot adjustment. Remove
this adapter after an audited Flutter OH upgrade supports onReorderItem.
"""
import os
from pathlib import Path
import sys

PATCHES = {
    'lib/page/settings_page/ai_reading_skills.dart': (
        'onReorderItem: (oldIndex, newIndex) {',
        'onReorder: (oldIndex, newIndex) {\n'
        '        if (newIndex > oldIndex) newIndex -= 1;'),
    'lib/page/settings_page/selection_toolbar.dart': (
        'onReorderItem: (a, b) => _reorder(a, b, annotations),',
        'onReorder: (a, b) => _reorder(a, b > a ? b - 1 : b, annotations),'),
}


def plan(root):
    result = {}
    for relative, (before, after) in PATCHES.items():
        path = root / relative
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('App source must remain inside the checkout')
        text = path.read_text()
        if text.count(before) != 1 or text.count('onReorderItem:') != 1:
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
    print('Adapted two reorder callbacks with index normalization; canonical source unchanged.')


if __name__ == '__main__':
    try:
        install(Path.cwd())
    except (OSError, ValueError) as error:
        sys.exit(str(error))
