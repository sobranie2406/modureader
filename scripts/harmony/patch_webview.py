"""Install the pinned WebView compatibility adapters in a Linux Actions checkout.

Run AFTER the initial `flutter pub get`. This command copies only verified Git
files from the three resolved packages, never edits PUB_CACHE, merges the existing
pubspec_overrides.yaml, and runs flutter pub get again with the explicit OH SDK.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urljoin, urlparse

import yaml

from webview_615_patch import PACKAGES, PIN, replacements, transform

REPOSITORY = 'https://gitcode.com/CPF-Flutter/flutter_inappwebview.git'
DESTINATION = Path('build/harmony-adapters')


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def package_roots(root):
    config = root / '.dart_tool/package_config.json'
    data = json.loads(config.read_text())
    roots = {}
    for package in data['packages']:
        uri = urlparse(urljoin(config.as_uri(), package['rootUri']))
        if uri.scheme != 'file' or uri.netloc not in ('', 'localhost'):
            raise ValueError('Only resolved local file package roots are supported')
        roots[package['name']] = Path(unquote(uri.path)).resolve()
    return roots


def assert_runner(root):
    if (os.environ.get('GITHUB_ACTIONS') != 'true' or
            os.environ.get('RUNNER_OS') != 'Linux' or
            not os.environ.get('GITHUB_WORKSPACE') or
            Path(os.environ['GITHUB_WORKSPACE']).resolve() != root):
        raise ValueError('Run only in the Linux GitHub Actions temporary checkout')
    sdk = os.environ.get('MODU_OHOS_FLUTTER')
    if not sdk or not (Path(sdk) / 'bin/flutter').is_file():
        raise ValueError('MODU_OHOS_FLUTTER must select the isolated Flutter OH SDK')
    return Path(sdk).resolve() / 'bin/flutter'


def verified_files(package_root, package, description):
    if (description.get('resolved-ref') != PIN or description.get('ref') != PIN or
            description.get('url') != REPOSITORY or description.get('path') != package):
        raise ValueError(f'{package}: lockfile must resolve the exact approved repository/path/pin {PIN}')
    repo = Path(git(package_root, 'rev-parse', '--show-toplevel')).resolve()
    if package_root != repo / package or git(repo, 'rev-parse', 'HEAD') != PIN:
        raise ValueError(f'{package}: package_config and Git checkout do not match the pin')
    files = {}
    # Read the COMMIT tree, not the index. Reject modified tracked source and
    # symlinks; ignore generated/cache/untracked files rather than copying them.
    tree = git(repo, 'ls-tree', '-r', PIN, '--', package)
    for entry in tree.splitlines():
        metadata, name = entry.split('\t', 1)
        mode, kind, oid = metadata.split()
        relative = Path(name)
        if kind != 'blob' or mode not in ('100644', '100755'):
            raise ValueError(f'{package}: unsupported Git entry {name}')
        source = repo / relative
        if source.is_symlink() or source.resolve() != source:
            raise ValueError(f'{package}: symlink source {name}')
        content = source.read_bytes()
        actual = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
        if actual != oid:
            raise ValueError(f'{package}: resolved source differs from pinned Git blob: {name}')
        files[str(relative)] = (content, int(mode[-3:], 8))
    if f'{package}/pubspec.yaml' not in files:
        raise ValueError(f'{package}: no pinned manifest')
    return files


def plan(root):
    """Read-only preflight; returns a complete, verified adapter write plan."""
    roots = package_roots(root)
    lock = yaml.safe_load((root / 'pubspec.lock').read_text())
    overlay_path = root / 'pubspec_overrides.yaml'
    overlay = yaml.safe_load(overlay_path.read_text())
    if not isinstance(overlay, dict) or not isinstance(overlay.get('dependency_overrides'), dict):
        raise ValueError('Prepare the Harmony dependency overlay before patching')
    files = {}
    for package in PACKAGES:
        entry = lock['packages'][package]
        if entry.get('source') != 'git':
            raise ValueError(f'{package}: initial resolution must use the pinned Git package')
        files.update(verified_files(roots[package], package, entry['description']))
    sources = {path: files[path][0].decode('utf-8') for path, *_ in replacements()}
    for path, source in transform(sources).items():
        files[path] = (source.encode('utf-8'), files[path][1])
    for package in PACKAGES:
        manifest_path = f'{package}/pubspec.yaml'
        manifest = yaml.safe_load(files[manifest_path][0])
        if manifest.get('name') != package:
            raise ValueError(f'{package}: manifest name mismatch')
        # Upstream uses ../sibling path dependencies. Three siblings are copied;
        # the others must remain the ALREADY RESOLVED packages, not missing paths
        # under build/ or a second, unpinned Git checkout.
        for name, dependency in manifest.get('dependencies', {}).items():
            if isinstance(dependency, dict) and 'path' in dependency:
                if name in PACKAGES:
                    dependency['path'] = f'../{name}'
                elif name in roots:
                    dependency['path'] = str(roots[name])
                else:
                    raise ValueError(f'{package}: unresolved sibling dependency {name}')
        files[manifest_path] = (yaml.safe_dump(manifest, sort_keys=False).encode(), 0o644)
        overlay['dependency_overrides'][package] = {'path': str(DESTINATION / package)}
    return files, overlay


def install(root):
    root = root.resolve()
    flutter = assert_runner(root)
    destination = root / DESTINATION
    if destination.exists() or destination.is_symlink():
        raise ValueError('Refusing to overwrite existing build/harmony-adapters; use a fresh checkout')
    if (root / 'build').is_symlink():
        raise ValueError('Refusing a symlink build directory')
    overlay_path = root / 'pubspec_overrides.yaml'
    if overlay_path.is_symlink():
        raise ValueError('Refusing a symlink dependency overlay')
    files, overlay = plan(root)
    original_overlay = overlay_path.read_bytes()
    original_lock = (root / 'pubspec.lock').read_bytes()
    original_config = (root / '.dart_tool/package_config.json').read_bytes()
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.webview-', dir=destination.parent))
    published = False
    try:
        for name, (content, mode) in files.items():
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            target.chmod(mode)
        (stage / 'PROVENANCE.json').write_text(json.dumps({
            'repository': REPOSITORY, 'commit': PIN, 'packages': list(PACKAGES),
            'patch_sha256': hashlib.sha256(Path(__file__).with_name('webview_615_patch.py').read_bytes()).hexdigest(),
            'files': {name: hashlib.sha256(data).hexdigest() for name, (data, _) in files.items()},
        }, indent=2) + '\n')
        stage.rename(destination)
        published = True
        overlay_path.write_text(yaml.safe_dump(overlay, sort_keys=False))
        subprocess.run([str(flutter), 'pub', 'get'], cwd=root, check=True)
        resolved = package_roots(root)
        for package in PACKAGES:
            if resolved[package] != destination / package:
                raise ValueError(f'{package}: pub get did not select the patched adapter')
    except BaseException:
        # Restore resolution inputs on failure, retain generated adapters/logs for
        # inspection. The failed command must stop CI; no build may follow it.
        if published:
            overlay_path.write_bytes(original_overlay)
            (root / 'pubspec.lock').write_bytes(original_lock)
            (root / '.dart_tool/package_config.json').write_bytes(original_config)
        raise
    finally:
        if not published:
            shutil.rmtree(stage)
    print(f'Installed three verified WebView adapters from {PIN}; second pub get succeeded.')


if __name__ == '__main__':
    try:
        install(Path.cwd())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
