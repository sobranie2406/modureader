import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// The GitHub release tag that hosts the prebuilt binaries. This tracks the
/// native crate, not the package version: bump it only when the Rust sources
/// under `native/` change and a new release carries the rebuilt binaries.
///
/// v0.2.0 adds the `tk_token_to_id` and `tk_id_to_token` symbols, so the
/// binaries under this tag must be the rebuilt ones or a prebuilt install will
/// fail to resolve them.
///
/// v0.5.0 changes `tk_encode`, `tk_encode_offsets` and `tk_token_to_id` to take
/// an explicit `(pointer, length)` instead of a NUL-terminated string, so the
/// binaries under this tag are ABI-incompatible with the older Dart bindings:
/// the tag must move in lockstep with the package that ships those bindings.
/// `v0.4.0` already exists as a release cut before this change, so it still
/// serves the old, NUL-terminated signatures; reusing that tag here would
/// silently hand the new bindings a binary that reads the wrong argument as
/// `out_len` and crashes.
const _version = '0.5.0';

/// SHA-256 over the crate sources the binaries under [_version] were built
/// from, in the order `test/prebuilt_tag_test.dart` hashes them. Public
/// because that test is the only reader: the hook itself never needs it.
///
/// The comment above says to bump the tag whenever `native/` changes, and 0.5.0
/// shipped anyway with the tag left behind — every prebuilt install segfaulted
/// on the first call for two days. A note cannot fail; this can. Change the
/// crate and the test goes red until the tag moves and a release carries the
/// rebuilt binaries.
const nativeSourcesDigest =
    'ee63b883e1219c17d3c868b20323f3ad8de07d3167aa9a7d449ca1655161fb64';
const _releaseBase =
    'https://github.com/Yusufihsangorgel/tokenizers/releases/download/v$_version';

/// Provides the `tokenizers_ffi` native library for `dart:ffi`'s `@Native`
/// lookups. It prefers a prebuilt binary from the GitHub release so consumers
/// need no toolchain, and falls back to building the Rust crate with cargo.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final os = input.config.code.targetOS;
    final arch = input.config.code.targetArchitecture;
    final crateDir = input.packageRoot.resolve('native/tokenizers_ffi/');
    final localName = _localLibraryName(os);

    Uri? library;
    if (os == OS.android || os == OS.iOS) {
      library = await _mobileBuild(input, crateDir, os, arch);
    }
    var downloadFailed = false;

    // 1) Prebuilt binary from the release: no toolchain required.
    final asset = _prebuiltAssetName(os, arch);
    if (library == null && asset != null) {
      final dest = input.outputDirectory.resolve(localName);
      if (await _download('$_releaseBase/$asset', dest)) {
        library = dest;
      } else {
        // A prebuilt is published for this target but could not be fetched:
        // offline, proxied, or GitHub rate-limited. Fall through to a source
        // build, but remember why, so if that also fails the message names the
        // real first cause instead of blaming a missing toolchain.
        downloadFailed = true;
      }
    }

    // 2) Build from source with cargo (needs a Rust toolchain, and a host
    //    whose target matches: this hook does not cross-compile).
    library ??= await _cargoBuild(
      crateDir,
      localName,
      os,
      arch,
      downloadFailed: downloadFailed,
    );

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: library,
      ),
    );
    output.dependencies.addAll([
      crateDir.resolve('src/lib.rs'),
      crateDir.resolve('Cargo.toml'),
    ]);
  });
}

String _localLibraryName(OS os) => switch (os) {
  OS.macOS || OS.iOS => 'libtokenizers_ffi.dylib',
  OS.windows => 'tokenizers_ffi.dll',
  _ => 'libtokenizers_ffi.so',
};

/// The release asset name for a target, or null if no prebuilt is published.
String? _prebuiltAssetName(OS os, Architecture arch) {
  final platform = switch ((os, arch)) {
    (OS.macOS, Architecture.arm64) => 'macos-arm64',
    (OS.macOS, Architecture.x64) => 'macos-x64',
    (OS.linux, Architecture.x64) => 'linux-x64',
    (OS.windows, Architecture.x64) => 'windows-x64',
    _ => null,
  };
  if (platform == null) return null;
  return os == OS.windows
      ? 'tokenizers_ffi-$platform.dll'
      : 'libtokenizers_ffi-$platform.${os == OS.macOS ? 'dylib' : 'so'}';
}

Future<bool> _download(String url, Uri dest) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) return false;
    final file = File.fromUri(dest);
    await file.parent.create(recursive: true);
    await response.pipe(file.openWrite());
    return true;
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<Uri> _cargoBuild(
  Uri crateDir,
  String localName,
  OS os,
  Architecture arch, {
  required bool downloadFailed,
}) async {
  // `cargo build` compiles for the host. This hook passes no `--target`, so it
  // can only produce a library for the platform it runs on. A build targeting
  // Android or iOS from a desktop host would emit the wrong binary (or none),
  // so refuse it up front with a message that says what is missing rather than
  // failing obscurely deeper in.
  if (os == OS.android || os == OS.iOS) {
    throw Exception(
      'hf_tokenizers has no prebuilt binary for $os and cannot cross-compile '
      'it from source: the build hook builds for the host only. $os support '
      'needs a prebuilt in the GitHub release, which is not published yet. '
      'Track it at https://github.com/Yusufihsangorgel/tokenizers.',
    );
  }

  final ProcessResult result;
  try {
    result = await Process.run(
      _resolveCargo(),
      ['build', '--release', '--locked', '--target', _desktopTarget(os, arch)],
      workingDirectory: crateDir.toFilePath(),
      environment: _envWithCargoBin(),
    );
  } on ProcessException catch (error) {
    // cargo is not on PATH: Process.run throws rather than returning a
    // non-zero exit, so without this the hook crashes with a raw
    // ProcessException instead of telling the user what to install.
    throw Exception(
      _sourceBuildMessage(
        os,
        arch,
        'no Rust toolchain was found (${error.message})',
        downloadFailed: downloadFailed,
      ),
    );
  }
  if (result.exitCode != 0) {
    throw Exception(
      _sourceBuildMessage(
        os,
        arch,
        'the source build failed (exit ${result.exitCode})\n'
        '${result.stdout}\n${result.stderr}',
        downloadFailed: downloadFailed,
      ),
    );
  }
  return crateDir.resolve(
    'target/${_desktopTarget(os, arch)}/release/$localName',
  );
}

// Modu modification: compile the original Rust tokenizer for the actual target,
// never bundle a desktop host binary in an Android/iOS application.
String _desktopTarget(OS os, Architecture arch) => switch ((os, arch)) {
  (OS.windows, Architecture.arm64) => 'aarch64-pc-windows-msvc',
  (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
  (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',
  (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
  (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
  (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
  _ => throw UnsupportedError('Unsupported tokenizer target: $os $arch'),
};

Future<Uri> _mobileBuild(
  BuildInput input,
  Uri crateDir,
  OS os,
  Architecture arch,
) async {
  final triple = switch ((os, arch)) {
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',
    (OS.iOS, Architecture.arm64) =>
      input.config.code.iOS.targetSdk == IOSSdk.iPhoneOS
          ? 'aarch64-apple-ios'
          : 'aarch64-apple-ios-sim',
    (OS.iOS, Architecture.x64) => 'x86_64-apple-ios',
    _ => throw UnsupportedError('Unsupported mobile tokenizer: $os $arch'),
  };
  final env = _envWithCargoBin();
  final targetDir = input.outputDirectory.resolve('cargo/').toFilePath();
  env['CARGO_TARGET_DIR'] = targetDir;
  if (os == OS.android) {
    final compiler = input.config.code.cCompiler;
    if (compiler == null) throw StateError('Android NDK compiler missing');
    final api = input.config.code.android.targetNdkApi;
    final cc = compiler.compiler.resolve('$triple$api-clang').toFilePath();
    env['CARGO_TARGET_${triple.toUpperCase().replaceAll('-', '_')}_LINKER'] =
        cc;
    env['CC_${triple.replaceAll('-', '_')}'] = cc;
    env['AR_${triple.replaceAll('-', '_')}'] = compiler.archiver.toFilePath();
  } else {
    env['IPHONEOS_DEPLOYMENT_TARGET'] = input.config.code.iOS.targetVersion
        .toString();
    final sdk = input.config.code.iOS.targetSdk == IOSSdk.iPhoneOS
        ? 'iphoneos'
        : 'iphonesimulator';
    final result = await Process.run('xcrun', [
      '--sdk',
      sdk,
      '--show-sdk-path',
    ]);
    if (result.exitCode != 0)
      throw StateError('iOS SDK unavailable: ${result.stderr}');
    env['SDKROOT'] = result.stdout.toString().trim();
  }
  final result = await Process.run(
    _resolveCargo(),
    ['build', '--release', '--locked', '--target', triple],
    workingDirectory: crateDir.toFilePath(),
    environment: env,
  );
  if (result.exitCode != 0)
    throw StateError('Tokenizer $triple build failed: ${result.stderr}');
  final library = File('$targetDir/$triple/release/${_localLibraryName(os)}');
  if (!await library.exists())
    throw StateError('Tokenizer output missing: $triple');
  return library.uri;
}

/// A build-failure message that names the real first cause. A prebuilt exists
/// for the desktop targets, so the usual reason a source build runs at all is
/// that the download failed; say so, rather than pointing at the toolchain.
String _sourceBuildMessage(
  OS os,
  Architecture arch,
  String detail, {
  required bool downloadFailed,
}) {
  final lead = downloadFailed
      ? 'The prebuilt binary for $os $arch could not be downloaded '
            '(offline, proxied, or rate-limited?), and the source-build '
            'fallback then failed'
      : 'No prebuilt binary is published for $os $arch, and the source-build '
            'fallback failed';
  return '$lead: $detail\n'
      'Install a Rust toolchain from https://rustup.rs, or build on a target '
      'with a published prebuilt (macOS arm64/x64, Linux x64, Windows x64).';
}

/// `Process.run` does not inherit the login shell's PATH, so rustup's default
/// `~/.cargo/bin` location is checked too.
String _resolveCargo() {
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'];
  final exe = Platform.isWindows ? 'cargo.exe' : 'cargo';
  for (final candidate in [
    env['CARGO'],
    if (home != null) '$home/.cargo/bin/$exe',
  ]) {
    if (candidate != null && File(candidate).existsSync()) return candidate;
  }
  return exe;
}

Map<String, String> _envWithCargoBin() {
  final env = Map<String, String>.from(Platform.environment);
  final home = env['HOME'] ?? env['USERPROFILE'];
  if (home != null) {
    final sep = Platform.isWindows ? ';' : ':';
    env['PATH'] = '$home/.cargo/bin$sep${env['PATH'] ?? ''}';
  }
  return env;
}
