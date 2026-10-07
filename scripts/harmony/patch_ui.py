"""Cloud-only OHOS UI compatibility for three audited pub.dev releases.

Integration (workflow intentionally not changed): after the first Flutter OH
pub get, and optionally after patch_webview.py, run from the checkout root:
    python3 scripts/harmony/patch_ui.py
Requires Python 3.9+, PyYAML, Linux GitHub Actions, GITHUB_WORKSPACE equal to
the checkout, and MODU_OHOS_FLUTTER pointing to the isolated Flutter OH SDK.
PUB_CACHE defaults to ~/.pub-cache. No download, SDK install, or cache edit.

Copies resolved packages to build/harmony-ui-adapters, merges path overrides
(including existing WebView overrides), then runs that SDK's flutter pub get.
Only 40 case labels in 11 files change. Every OHOS label shares Android's
existing body; no default branch, stub, or native platform spoofing is added.
The commented-out math caret switch is deliberately untouched. Existing
Android branches which skip Apple-only behavior remain unchanged. Mongol IME
undo coalescing follows Android's composing-text policy; device UX is untested.

Versions, archive identities in pubspec.lock, and complete patched-file hashes
are pinned below. Extracted cache files are NOT claimed to be independently
verified against the archive hash. Symlinks/special files and source drift are
rejected. Upgrade requires a new source audit, not a wider replacement pattern.
On pub failure, restores overlay/lock/package_config, retains adapters for
diagnosis, and exits nonzero: stop CI and retry in a fresh checkout. Other pub
generated metadata is not rolled back. Root pubspec.yaml and lib never change.

Tests (no SDK execution): python3 -B test/harmony_ui_test.py
Tests read the locally resolved packages and use disposable fixture copies.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urljoin, urlparse

import yaml

DESTINATION = Path('build/harmony-ui-adapters')
PACKAGES = {
    'flex_color_scheme': ('8.3.0', '034d5720747e6af39b2ad090d82dd92d33fde68e7964f1814b714c9d49ddbd64'),
    'flutter_math_fork': ('0.7.4', '6d5f2f1aa57ae539ffb0a04bb39d2da67af74601d685a161aff7ce5bda5fa407'),
    'mongol': ('9.3.0', '52f54a14a558e5719e21f2be5ccd577c0a59d90b3dce8887f28ca79385fb7e53'),
}
# Each tuple is (full original SHA256, {original line: reviewed behavior}).
# Line anchors are executable case labels, not comments or general replacements.
PATCHES = {
    'flex_color_scheme/lib/src/flex_adaptive.dart': (
        'c13a8d25b8fc9ab2255175d05ebf47a0862a0c7f9a377e0a981eda9153810231',
        {400: 'Android mobile web adaptive policy', 415: 'Android native adaptive policy'}),
    'flex_color_scheme/lib/src/flex_color_scheme.dart': (
        'b17686b3e1bf7617f6aeee94bee9aed624a5ecc69d6891ae5417b165b885274f',
        {5786: 'Standard mobile density', 7270: '14px mobile tooltip font'}),
    'flutter_math_fork/lib/src/render/layout/line_editable.dart': (
        '8de399571824fc87e55b5bf6cfb82fa24ff27c17a667edac0670f9cf991ecca5',
        {479: 'Material caret rectangle'}),
    'flutter_math_fork/lib/src/widgets/selectable.dart': (
        '8137eb52de4d68e4987e7e64aab9fa6b78282715c58889ca956a71e68210ec04',
        {293: 'Material selection controls and cursor', 480: 'Skip Apple-only long-press scroll'}),
    'flutter_math_fork/lib/src/widgets/selection/gesture_detector_builder_selectable.dart': (
        '51a1df0cac356222b0e48288deb7bfa343c52e52984fabc0dd10e7c0a72a327f',
        {51: 'Material tap position selection'}),
    'mongol/lib/src/editing/mongol_editable_text.dart': (
        '5291cfe9b9b010eb78eef165c372847c96c005fd5e4010c928c9e6546764aa31',
        {1232: 'Use common autofill keyboard inference, not Apple-specific table',
         1491: 'Select-all enabled when selection is incomplete',
         1534: 'Copy collapses selection and hides mobile handles',
         1635: 'Retain mobile toolbar on select-all',
         1645: 'Scroll selection extent into view',
         3424: 'Mobile touch outside does not drop focus',
         4558: 'Coalesce composing text in mobile IME undo history'}),
    'mongol/lib/src/editing/mongol_render_editable.dart': (
        '48caf86112c2cd9218e647f972b1002246b68230d4166d7898b5936520c5cfd4',
        {1914: 'Android read-only word-boundary selection', 1990: 'Material vertical caret geometry'}),
    'mongol/lib/src/editing/mongol_text_editing_shortcuts.dart': (
        'fa99d72565b0acf05c06ce808948f6b3eea9d0d8b25506f244661983265975d1',
        {271: 'Existing Android editing shortcuts'}),
    'mongol/lib/src/editing/mongol_text_field.dart': (
        '642ee720ee23d44ab0a07757a113b581420291b9dc137a6dc3f0c80be6a10ffd',
        {71: 'Long-press drag word range', 103: 'Long-press word selection and feedback',
         1379: 'Skip Apple-only long-press scroll', 1469: 'Mobile Material selection and cursor'}),
    'mongol/lib/src/editing/text_selection/mongol_text_selection.dart': (
        '5f0379a1e0d9416a8269155bf9b645373e65dfd5419726bbb816e90bf7271121',
        {508: 'Selection end handle drag', 609: 'Selection start handle drag',
         724: 'Show touch magnifier', 737: 'Hide touch magnifier',
         971: 'Mobile tap-down hides toolbar; selects on tap-up',
         1074: 'Tap-up selection and spelling toolbar', 1204: 'Long-press word selection',
         1258: 'Long-press drag word range', 1313: 'Toggle toolbar on selection tap',
         1442: 'Triple tap selects paragraph', 1497: 'Shift drag extends selection',
         1529: 'Touch drag moves caret, precise pointer selects text',
         1620: 'Mobile triple-tap pointer selection',
         1695: 'Mobile touch versus precise-pointer drag update',
         2090: 'Selection handle haptic feedback', 2698: 'Cycle consecutive tap count at three',
         2836: 'Mobile horizontal drag recognizer for vertical text'}),
    'mongol/lib/src/menu/mongol_popup_menu.dart': (
        'aeea42afcaaf24242db87f64135779f74849ade597b2b78bf631a2fb41e1138e',
        {1038: 'Material popup-menu accessibility label'}),
}


class UniqueLoader(yaml.SafeLoader):
    """Do not silently lose existing overrides through duplicate YAML keys."""


def _mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ValueError(f'Duplicate YAML key: {key}')
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _mapping)


def load_yaml(data):
    result = yaml.load(data, Loader=UniqueLoader)
    if not isinstance(result, dict):
        raise ValueError('Expected a YAML mapping')
    return result


def no_symlinks(path):
    for component in (path, *path.parents):
        if component.is_symlink():
            raise ValueError(f'Refusing symlink: {component}')


def package_roots(root):
    config = root / '.dart_tool/package_config.json'
    no_symlinks(config)
    data = json.loads(config.read_bytes())
    if data.get('configVersion') != 2:
        raise ValueError('Expected package_config version 2')
    roots = {}
    for entry in data['packages']:
        name = entry['name']
        if name in roots:
            raise ValueError(f'Duplicate package_config name: {name}')
        uri = urlparse(urljoin(config.as_uri(), entry['rootUri']))
        if (uri.scheme != 'file' or uri.netloc not in ('', 'localhost') or
                uri.query or uri.fragment):
            raise ValueError(f'{name}: expected a local file rootUri')
        path = Path(unquote(uri.path))
        if name in PACKAGES:
            no_symlinks(path)
            if entry.get('packageUri') != 'lib/':
                raise ValueError(f'{name}: expected packageUri lib/')
        roots[name] = path.resolve()
    return roots


def transform(name, content):
    digest, anchors = PATCHES[name]
    if hashlib.sha256(content).hexdigest() != digest:
        raise ValueError(f'{name}: audited source SHA256 mismatch; re-audit required')
    lines = content.splitlines(keepends=True)
    for number in sorted(anchors, reverse=True):
        line = lines[number - 1]
        if line.strip() != b'case TargetPlatform.android:':
            raise ValueError(f'{name}:{number}: Android anchor mismatch')
        lines.insert(number - 1, line.replace(b'TargetPlatform.android', b'TargetPlatform.ohos'))
    return b''.join(lines)


def assert_runner(root):
    if (sys.platform != 'linux' or os.environ.get('GITHUB_ACTIONS') != 'true' or
            os.environ.get('RUNNER_OS') != 'Linux' or
            not os.environ.get('GITHUB_WORKSPACE') or
            Path(os.environ['GITHUB_WORKSPACE']).resolve() != root):
        raise ValueError('Run only in the Linux GitHub Actions temporary checkout')
    sdk = os.environ.get('MODU_OHOS_FLUTTER')
    if not sdk or not Path(sdk).is_absolute() or not (Path(sdk) / 'bin/flutter').is_file():
        raise ValueError('MODU_OHOS_FLUTTER must select the isolated Flutter OH SDK')
    return Path(sdk).resolve() / 'bin/flutter'


def plan(root):
    """Read-only verification and in-memory copy/patch plan; no SDK execution."""
    for relative in ('pubspec.yaml', 'pubspec.lock', 'pubspec_overrides.yaml', 'build'):
        no_symlinks(root / relative)
    roots = package_roots(root)
    lock = load_yaml((root / 'pubspec.lock').read_bytes())['packages']
    manifest = load_yaml((root / 'pubspec.yaml').read_bytes())
    overlay_path = root / 'pubspec_overrides.yaml'
    overlay = load_yaml(overlay_path.read_bytes()) if overlay_path.exists() else {}
    overrides = dict(manifest.get('dependency_overrides', {}))
    overrides.update(overlay.get('dependency_overrides', {}))
    cache = Path(os.environ.get('PUB_CACHE', str(Path.home() / '.pub-cache'))).absolute()
    no_symlinks(cache)
    files = {}
    for package, (version, archive_hash) in PACKAGES.items():
        entry = lock[package]
        description = entry.get('description', {})
        if (entry.get('source') != 'hosted' or entry.get('version') != version or
                not isinstance(description, dict) or description.get('name') != package or
                description.get('url') not in ('https://pub.dev', 'https://pub.dev/') or
                description.get('sha256') != archive_hash):
            raise ValueError(f'{package}: expected audited hosted pub.dev {version} and archive SHA256')
        expected = cache / 'hosted/pub.dev' / f'{package}-{version}'
        no_symlinks(expected)
        if roots[package] != expected or not expected.is_dir():
            raise ValueError(f'{package}: package_config root differs from expected hosted cache path')
        package_manifest_path = expected / 'pubspec.yaml'
        if not stat.S_ISREG(package_manifest_path.lstat().st_mode):
            raise ValueError(f'{package}: symlink/special manifest')
        package_manifest = load_yaml(package_manifest_path.read_bytes())
        if package_manifest.get('name') != package or package_manifest.get('version') != version:
            raise ValueError(f'{package}: manifest name/version mismatch')
        # Check directory entries too: never follow symlinks or copy device/FIFO files.
        for directory, directories, filenames in os.walk(expected, followlinks=False):
            for name in directories + filenames:
                source = Path(directory) / name
                mode = source.lstat().st_mode
                if not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)):
                    raise ValueError(f'{package}: symlink/special cache entry: {source}')
                if stat.S_ISREG(mode):
                    relative = str(Path(package) / source.relative_to(expected))
                    files[relative] = (source.read_bytes(), stat.S_IMODE(mode) & 0o777)
        overrides[package] = {'path': str(DESTINATION / package)}
    for name in PATCHES:
        data, mode = files[name]
        files[name] = (transform(name, data), mode)
    overlay['dependency_overrides'] = overrides
    return files, overlay


def install(root):
    root = root.resolve()
    flutter = assert_runner(root)
    destination = root / DESTINATION
    no_symlinks(destination)
    if destination.exists():
        raise ValueError('Adapters already exist; use a fresh checkout')
    files, overlay = plan(root)
    overlay_path = root / 'pubspec_overrides.yaml'
    tracked = (overlay_path, root / 'pubspec.lock', root / '.dart_tool/package_config.json')
    originals = {p: p.read_bytes() if p.exists() else None for p in tracked}
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.harmony-ui-', dir=destination.parent))
    published = False
    try:
        for name, (content, mode) in files.items():
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            target.chmod(mode)
        (stage / 'PROVENANCE.json').write_text(json.dumps({
            'packages': PACKAGES, 'reviewed_cases': PATCHES,
            'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'files': {name: hashlib.sha256(data).hexdigest() for name, (data, _) in files.items()},
        }, indent=2) + '\n')
        stage.rename(destination)
        published = True
        overlay_path.write_text(yaml.safe_dump(overlay, sort_keys=False))
        subprocess.run([str(flutter), 'pub', 'get'], cwd=root, check=True)
        resolved = package_roots(root)
        lock = load_yaml((root / 'pubspec.lock').read_bytes())['packages']
        if load_yaml(overlay_path.read_bytes()) != overlay:
            raise ValueError('pub get unexpectedly changed the dependency overlay')
        for package, (version, _) in PACKAGES.items():
            if (resolved[package] != destination / package or
                    lock[package].get('source') != 'path' or lock[package].get('version') != version):
                raise ValueError(f'{package}: pub get did not resolve the exact patched adapter')
    except BaseException:
        if published:
            for path, original in originals.items():
                if original is None:
                    path.unlink(missing_ok=True)
                else:
                    path.write_bytes(original)
        raise
    finally:
        if not published:
            shutil.rmtree(stage)
    print('Installed three pinned UI adapters (40 Android-shared OHOS cases); pub get verified.')


if __name__ == '__main__':
    try:
        install(Path.cwd())
    except (OSError, ValueError, KeyError, TypeError, yaml.YAMLError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
