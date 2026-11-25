"""Adapt the pinned Linux WebView plugin to the bundled WPEPlatform."""
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
cmake_checks = {
    'set(CMAKE_REQUIRED_LIBRARIES ${WPE_WEBKIT_LIBRARIES} ${WPE_PLATFORM_LIBRARIES})':
        'set(CMAKE_REQUIRED_LIBRARIES PkgConfig::WPE_WEBKIT PkgConfig::WPE_PLATFORM)',
    '''pkg_check_modules(LIBWPE QUIET IMPORTED_TARGET wpe-1.0)
if(NOT LIBWPE_FOUND)
  message(FATAL_ERROR "libwpe (wpe-1.0) not found. Please install libwpe-1.0-dev.")
endif()''': '''if(HAVE_WPE_FDO)
  pkg_check_modules(LIBWPE REQUIRED IMPORTED_TARGET wpe-1.0)
endif()''',
}
for target in ('${PLUGIN_NAME}', '${TEST_RUNNER}'):
    line = f'target_link_libraries({target} PRIVATE PkgConfig::LIBWPE)'
    cmake_checks[line] = f'if(HAVE_WPE_FDO)\n  {line}\nendif()'

settings = root / 'linux/in_app_webview/in_app_webview_settings.cc'
settings_checks = {'WPE_SETTING_DISABLE_ANIMATIONS': 'WPE_SETTING_REDUCED_MOTION'}
pending = {}
for source, checks in ((cmake, cmake_checks), (settings, settings_checks)):
    before = source.read_text()
    after = before
    for old, new in checks.items():
        if after.count(new) == 1:
            continue
        if after.count(old) != 1:
            raise RuntimeError(f'Review the WPEPlatform build adjustment for {source.name}')
        after = after.replace(old, new)
    if after != before:
        pending[source] = after
for source, content in pending.items():
    source.write_text(content)
