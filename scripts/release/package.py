"""Package real release outputs, checking architecture before creating archives."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import struct
import subprocess
import zipfile
from verify_mobile import verify_android_apk, verify_apple_bundle
from bundle_models import verify_archive, verify_directory

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "dist-release"


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def write_checksum(path):
    with path.open("rb") as artifact:
        digest = hashlib.file_digest(artifact, "sha256").hexdigest()
    # Binary output preserves LF on Windows as well: CRLF makes Unix checksum
    # readers interpret the carriage return as part of the artifact filename.
    path.with_name(path.name + ".sha256").write_bytes(
        f"{digest}  {path.name}\n".encode("utf-8"))


def one(pattern):
    files = list(ROOT.glob(pattern))
    if len(files) != 1:
        raise RuntimeError(f"Expected one {pattern}, got {files}")
    return files[0]


def verify(path, platform, arch):
    data = path.read_bytes()[:4096]
    if platform == "windows":
        offset = struct.unpack_from("<I", data, 0x3C)[0]
        assert data[:2] == b"MZ" and data[offset:offset+4] == b"PE\0\0", path
        machine = struct.unpack_from("<H", data, offset+4)[0]
        assert machine == {"x64": 0x8664, "arm64": 0xAA64}[arch], (path, machine)
    elif platform == "linux":
        assert data[:5] == b"\x7fELF\x02", path
        machine = struct.unpack_from("<H", data, 18)[0]
        assert machine == {"x64": 62, "arm64": 183}[arch], (path, machine)
    else:
        expected = "x86_64" if arch == "x64" else "arm64"
        assert expected in run("lipo", "-archs", str(path)).split(), path


def notices(folder, platform):
    folder.mkdir(parents=True, exist_ok=True)
    for name in ("LICENSE", "NOTICE", "UPSTREAM.md", "PRIVACY.md"):
        shutil.copy2(ROOT / name, folder / name)
    shutil.copytree(ROOT / "LICENSES", folder / "LICENSES", dirs_exist_ok=True)
    shutil.copy2(ROOT / "docs/RELEASING.md", folder / "INSTALL.md")
    sha = run("git", "rev-parse", "HEAD")
    (folder / "SOURCE.txt").write_text(
        f"Modu / 默读 — derived from Anx Reader and ReadAny\n"
        f"GPL-3.0-or-later. Corresponding source revision: {sha}\n"
        f"https://github.com/sobranie2406/modureader/tree/{sha}\n"
        f"https://github.com/sobranie2406/modureader/archive/{sha}.tar.gz\n"
        "Dependency versions and source URLs: pubspec.lock, UPSTREAM.md.\n",
        encoding="utf-8",
    )
    if platform == "linux":
        source_packages = []
        for package in ("libwpewebkit-2.0-1", "libwpe-1.0-1", "libwpebackend-fdo-1.0-1"):
            copyright_file = Path("/usr/share/doc") / package / "copyright"
            shutil.copy2(copyright_file, folder / "LICENSES" / f"{package}-copyright.txt")
            source_packages.append(run("dpkg-query", "--show",
                "--showformat=${source:Package} ${source:Version}", package))
        with (folder / "SOURCE.txt").open("a", encoding="utf-8") as source:
            source.write("\nBundled WPE libraries — Debian corresponding source packages:\n")
            source.write("\n".join(source_packages))
            source.write("\nRetrieve with apt-get source PACKAGE=VERSION after enabling matching deb-src repositories.\n")


def package(platform, arch, version):
    suffix = {"macos": "-unnotarized", "ios": "-unsigned"}.get(platform, "")
    name = f"Modu-{version}-{platform}-{arch}{suffix}"
    stage = OUT / "staging" / name
    if stage.exists():
        raise RuntimeError(f"Refusing to overwrite existing staging folder: {stage}")
    stage.mkdir(parents=True)
    if platform == "android":
        abi = {"arm64": "arm64-v8a", "x64": "x86_64"}[arch]
        apk = ROOT / f"build/app/outputs/flutter-apk/app-{abi}-release.apk"
        verify_android_apk(apk, arch)
        with zipfile.ZipFile(apk) as archive:
            verify_archive(archive, 'assets/flutter_assets/')
            assert f"lib/{abi}/libapp.so" in archive.namelist()
            assert f"lib/{abi}/libflutter.so" in archive.namelist()
        # Gradle must have signed the APK; verify it, do not silently ship debug.
        sdk = Path(os.environ["ANDROID_HOME"])
        apksigner = sorted((sdk / "build-tools").glob("*/apksigner"))[-1]
        run(str(apksigner.parent / 'zipalign'), '-c', '-P', '16', '4', str(apk))
        result = run(str(apksigner), "verify", "--verbose", "--print-certs", str(apk))
        expected = (ROOT / "docs/android-signing-certificate.sha256").read_text().strip()
        fingerprints = [line.rsplit(":", 1)[1].strip().lower() for line in result.splitlines()
                        if "certificate SHA-256 digest:" in line]
        assert fingerprints == [expected], "APK is not signed by the Modu release identity"
        shutil.copy2(apk, OUT / f"{name}.apk")
        notices(stage, platform)
        shutil.make_archive(str(OUT / f"{name}-notices"), "zip", stage)
        return
    if platform == "windows":
        bundle = ROOT / f"build/windows/{arch}/runner/Release"
        for binary in ("modu.exe", "flutter_windows.dll", "onnxruntime.dll", "tokenizers_ffi.dll"):
            verify(bundle / binary, platform, arch)
        shutil.copytree(bundle, stage, dirs_exist_ok=True)
        verify_directory(stage / 'data/flutter_assets')
    elif platform == "linux":
        bundle = ROOT / f"build/linux/{arch}/release/bundle"
        verify(bundle / "modu", platform, arch)
        dependencies = run("ldd", str(bundle / "modu"))
        if "not found" in dependencies:
            raise RuntimeError(f"Unresolved Linux runtime libraries:\n{dependencies}")
        for binary in bundle.rglob("*tokenizers*.so"):
            verify(binary, platform, arch)
        shutil.copytree(bundle, stage, dirs_exist_ok=True, symlinks=True)
        verify_directory(stage / 'data/flutter_assets')
    elif platform == "macos":
        app = one("build/macos/Build/Products/Release/*.app")
        verify_apple_bundle(app, version)
        verify_directory(app / 'Contents/Frameworks/App.framework/Resources/flutter_assets')
        executable = run("/usr/libexec/PlistBuddy", "-c", "Print CFBundleExecutable", str(app / "Contents/Info.plist"))
        verify(app / "Contents/MacOS" / executable, platform, arch)
        subprocess.run(["ditto", str(app), str(stage / app.name)], check=True)
        # Flutter's CI build can leave an invalid resource seal. Seal the final
        # copied bundle with the agreed ad-hoc identity, preserving entitlements.
        subprocess.run(["codesign", "--force", "--deep", "--sign", "-",
                        "--entitlements", str(ROOT / "macos/Runner/Release.entitlements"),
                        str(stage / app.name)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(stage / app.name)], check=True)
    elif platform == "ios":
        app = one("build/ios/iphoneos/*.app")
        verify_apple_bundle(app, version)
        verify_directory(app / 'Frameworks/App.framework/flutter_assets')
        executable = run("/usr/libexec/PlistBuddy", "-c", "Print CFBundleExecutable", str(app / "Info.plist"))
        verify(app / executable, platform, arch)
        (stage / "Payload").mkdir()
        subprocess.run(["ditto", str(app), str(stage / "Payload" / app.name)], check=True)
    else:
        raise ValueError(platform)
    notices(stage, platform)
    if platform == "ios":
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", str(stage), str(OUT / f"{name}.ipa")], check=True)
    else:
        from native_installers import build
        build(stage, platform, arch, version, OUT)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=["macos", "windows", "linux", "android", "ios"])
    parser.add_argument("arch", choices=["x64", "arm64"])
    args = parser.parse_args()
    version = next(line.split(":", 1)[1].strip().split("+")[0] for line in (ROOT / "pubspec.yaml").read_text().splitlines() if line.startswith("version:"))
    os.chdir(ROOT)
    OUT.mkdir(exist_ok=True)
    package(args.platform, args.arch, version)
    for path in OUT.iterdir():
        if path.is_file() and path.suffix != ".sha256":
            write_checksum(path)
