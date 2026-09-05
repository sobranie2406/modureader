"""Check native package contents and dynamic dependency resolution in CI."""
import os
from pathlib import Path
import subprocess
import sys

from native_installers import verify_payload

if os.environ.get('GITHUB_ACTIONS') != 'true' or sys.platform != 'linux':
    raise RuntimeError('Requires an ephemeral Linux CI runner')
bundle = Path('/opt/modureader')
verify_payload(bundle, 'linux', sys.argv[1])
for path in [bundle / 'modu', *(bundle / 'lib').glob('*.so*')]:
    result = subprocess.run(['ldd', str(path)], capture_output=True, text=True)
    if result.returncode != 0 or 'not found' in result.stdout:
        raise RuntimeError(f'Unresolved runtime dependencies: {path}\n{result.stdout}\n{result.stderr}')
print('Installed native payload and all bundled dynamic-library dependencies verified')
