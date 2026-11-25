"""Build the relocatable WPE runtime and SDK on Ubuntu 24.04 x64."""

import argparse
import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile


VERSION = "2.54.3"
ARCHIVE = f"wpewebkit-{VERSION}.tar.xz"
SOURCE_URL = f"https://wpewebkit.org/releases/{ARCHIVE}"
SOURCE_SHA256 = "787afd32ae23eac061621465390f44a462e874a9ebaba0b65521d7237fa8a5e4"
PATCH = Path(__file__).with_name("wpe-appimage-relocation.patch").resolve()


def run(*command, **kwargs):
    subprocess.run(command, check=True, **kwargs)


def configure(source, build, prefix):
    options = {
        "PORT": "WPE",
        "CMAKE_BUILD_TYPE": "Release",
        "CMAKE_C_COMPILER": "clang-18",
        "CMAKE_CXX_COMPILER": "clang++-18",
        "CMAKE_EXE_LINKER_FLAGS": "-fuse-ld=lld-18",
        "CMAKE_SHARED_LINKER_FLAGS": "-fuse-ld=lld-18",
        "CMAKE_MODULE_LINKER_FLAGS": "-fuse-ld=lld-18",
        "CMAKE_INSTALL_PREFIX": prefix,
        "CMAKE_INSTALL_LIBDIR": "lib",
        "CMAKE_INSTALL_LIBEXECDIR": "libexec",
        "CMAKE_INSTALL_DATADIR": "share",
        "ENABLE_BUBBLEWRAP_SANDBOX": "ON",
        "BWRAP_EXECUTABLE": "/usr/bin/bwrap",
        "DBUS_PROXY_EXECUTABLE": "/usr/bin/xdg-dbus-proxy",
        "ENABLE_WPE_PLATFORM": "ON",
        "ENABLE_WPE_PLATFORM_HEADLESS": "ON",
        "ENABLE_WPE_PLATFORM_WAYLAND": "ON",
        "ENABLE_WPE_PLATFORM_DRM": "OFF",
        "ENABLE_WPE_LEGACY_API": "OFF",
        "ENABLE_DOCUMENTATION": "OFF",
        "ENABLE_INTROSPECTION": "OFF",
        "ENABLE_WEBDRIVER": "OFF",
        "USE_LIBBACKTRACE": "OFF",
        "USE_SYSPROF_CAPTURE": "OFF",
    }
    run("cmake", "-S", source, "-B", build, "-G", "Ninja",
        *(f"-D{name}={value}" for name, value in options.items()),
        env={**os.environ, "WEBKIT_NINJA_LINK_MAX": "1"})
    cache = (build / "CMakeCache.txt").read_text(encoding="utf-8").splitlines()
    if "ENABLE_BUBBLEWRAP_SANDBOX:BOOL=ON" not in cache:
        raise RuntimeError("WPE was configured without the Bubblewrap sandbox")


def record_source(source, prefix):
    docs = prefix / "share/doc/modu-wpe"
    docs.mkdir(parents=True)
    (docs / "SOURCE.txt").write_text(
        f"WPE WebKit {VERSION}\nSource: {SOURCE_URL}\nSHA-256: {SOURCE_SHA256}\n"
        f"Local modifications: {PATCH.name}\n"
        "Built on Ubuntu 24.04 x64. The build recipe is included alongside the patch.\n",
        encoding="utf-8",
    )
    shutil.copy2(PATCH, docs)
    shutil.copy2(Path(__file__), docs)
    for license_file in (source / "Source").rglob("*"):
        name = license_file.name.upper()
        if name.startswith(("LICENSE", "COPYING")) and license_file.is_file():
            target = docs / "licenses" / license_file.relative_to(source / "Source")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(license_file, target)


def check_install(prefix):
    required = (
        "lib/libWPEWebKit-2.0.so.1",
        "lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so",
        "libexec/wpe-webkit-2.0/WPEWebProcess",
        "libexec/wpe-webkit-2.0/WPENetworkProcess",
        "libexec/wpe-webkit-2.0/WPEGPUProcess",
        "share/wpe-webkit-2.0/inspector.gresource",
    )
    for path in required:
        if not (prefix / path).is_file():
            raise RuntimeError(f"WPE installation is missing {path}")
    env = {**os.environ, "PKG_CONFIG_PATH": str(prefix / "lib/pkgconfig")}
    run("pkg-config", "--exists", f"wpe-webkit-2.0 = {VERSION}",
        "wpe-platform-2.0", "wpe-platform-headless-2.0", env=env)


def build_runtime(prefix, jobs, archive):
    distro = platform.freedesktop_os_release() if platform.system() == "Linux" else {}
    if (distro.get("ID"), distro.get("VERSION_ID"), platform.machine()) != (
        "ubuntu", "24.04", "x86_64",
    ):
        raise RuntimeError("Build the WPE SDK on Ubuntu 24.04 x64")
    if prefix.exists() and any(prefix.iterdir()):
        raise RuntimeError(f"WPE installation prefix must be empty: {prefix}")
    with tempfile.TemporaryDirectory(prefix="modu-wpe-build-") as temp:
        work = Path(temp)
        if archive is None:
            archive = work / ARCHIVE
            run("curl", "--fail", "--location", "--retry", "3",
                "--proto", "=https", "--output", archive, SOURCE_URL)
        with archive.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        if digest != SOURCE_SHA256:
            raise RuntimeError("WPE source archive SHA-256 does not match the release pin")
        with tarfile.open(archive, "r:xz") as tar:
            tar.extractall(work, filter="data")
        source = work / f"wpewebkit-{VERSION}"
        run("git", "apply", PATCH, cwd=source)

        build = work / "build"
        configure(source, build, prefix)
        run("cmake", "--build", build, "--parallel", str(jobs))
        run("cmake", "--install", build, "--strip")
        check_install(prefix)
        record_source(source, prefix)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prefix", type=Path)
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 1, 3))
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    build_runtime(args.prefix.resolve(), args.jobs, args.archive)
