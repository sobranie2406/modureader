"""Create Harmony-only overrides in a fresh runner checkout, never locally.

No SDK installation here. The normal manifest and lock file remain untouched.
JSON is also YAML, so pub can read the generated pubspec_overrides.yaml.
"""
import json
import os
from pathlib import Path
import re
import sys

import yaml


def overrides(root: Path) -> dict:
    manifest = yaml.safe_load((root / 'pubspec.yaml').read_text())
    result = dict(manifest.get('dependency_overrides', {}))
    for name in ('platform_overrides.json', 'audio_webview_overrides.json'):
        entries = json.loads((root / 'scripts/harmony' / name).read_text())
        for package, value in entries.items():
            if isinstance(value, dict) and 'git' in value:
                git = value['git']
                if not re.fullmatch(r'[0-9a-f]{40}', git.get('ref', '')):
                    raise ValueError(f'{package}: use a full pinned commit')
                if not git.get('url', '').startswith('https://gitcode.com/CPF-Flutter/'):
                    raise ValueError(f'{package}: unexpected adapter source')
            result[package] = value
    return {'dependency_overrides': result}


def prepare(root: Path) -> None:
    # This file alters dependency resolution, so intentionally refuse the
    # developer's normal workspace, even if called there by mistake.
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise ValueError('Run only on GitHub Actions in a fresh checkout')
    target = root / 'pubspec_overrides.yaml'
    if target.exists():
        raise ValueError('Refusing to replace an existing dependency overlay')
    data = overrides(root)
    with target.open('x') as output:
        json.dump(data, output, indent=2)
        output.write('\n')
    print(f'Harmony-only dependency overlay: {len(data["dependency_overrides"])} packages')


if __name__ == '__main__':
    try:
        prepare(Path.cwd())
    except (OSError, ValueError) as error:
        sys.exit(str(error))
