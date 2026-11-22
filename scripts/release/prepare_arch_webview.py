"""Make the pinned Linux WebView plugin's libwpe dependency legacy-only."""
import json
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import url2pathname


config = Path('.dart_tool/package_config.json').resolve(strict=True)
package = next(
    entry for entry in json.loads(config.read_text())['packages']
    if entry['name'] == 'flutter_inappwebview_linux'
)
uri = urlsplit(urljoin(config.as_uri(), package['rootUri']))
root = Path(url2pathname(uri.path))
if uri.scheme != 'file' or uri.netloc or root.name != 'flutter_inappwebview_linux-0.1.0-beta.1':
    raise RuntimeError('Review the WPEPlatform build adjustment for this WebView version')

cmake = root / 'linux/CMakeLists.txt'
before = cmake.read_text()
checks = {
    '''pkg_check_modules(LIBWPE QUIET IMPORTED_TARGET wpe-1.0)
if(NOT LIBWPE_FOUND)
  message(FATAL_ERROR "libwpe (wpe-1.0) not found. Please install libwpe-1.0-dev.")
endif()''': '''if(HAVE_WPE_FDO)
  pkg_check_modules(LIBWPE REQUIRED IMPORTED_TARGET wpe-1.0)
endif()''',
}
for target in ('${PLUGIN_NAME}', '${TEST_RUNNER}'):
    line = f'target_link_libraries({target} PRIVATE PkgConfig::LIBWPE)'
    checks[line] = f'if(HAVE_WPE_FDO)\n  {line}\nendif()'

after = before
for old, new in checks.items():
    if after.count(new) == 1:
        continue
    if after.count(old) != 1:
        raise RuntimeError('Review the WPEPlatform build adjustment for the updated CMake source')
    after = after.replace(old, new)
if after != before:
    cmake.write_text(after)
