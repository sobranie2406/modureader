import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// SAF grants an already-open descriptor, not permission to reopen its path.
/// Duplicate it for each stream and use positional reads; never copy at import.
File readOnlyBookFile(String path) {
  final file = File(path);
  if (!(Platform.isAndroid ||
          Platform.isLinux ||
          Platform.operatingSystem == 'ohos') ||
      !path.contains('/linked-book-access/linked-')) {
    return file;
  }
  try {
    final target = Link(path).targetSync();
    final match = RegExp(r'^/proc/self/fd/(\d+)$').firstMatch(target);
    if (match != null) return _DescriptorBookFile(file, int.parse(match[1]!));
  } on FileSystemException {
    // Missing/revoked access must fail as a missing file, never become a copy.
  }
  return file;
}

class _DescriptorIo {
  static final library = DynamicLibrary.open('libc.so');
  static final fcntl = library.lookupFunction<
      Int32 Function(Int32, Int32, VarArgs<(Int32,)>),
      int Function(int, int, int)>('fcntl');
  static int duplicate(int fd) => fcntl(fd, 1030, 0); // F_DUPFD_CLOEXEC
  static final close =
      library.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static final allocate = library.lookupFunction<
      Pointer<Uint8> Function(IntPtr), Pointer<Uint8> Function(int)>('malloc');
  static final release = library.lookupFunction<Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)>('free');
  static final read = library.lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int64),
      int Function(int, Pointer<Uint8>, int, int)>('pread64');
}

class _DescriptorBookFile implements File {
  _DescriptorBookFile(this.delegate, this.descriptor);
  final File delegate;
  final int descriptor;
  @override
  String get path => delegate.path;
  @override
  Uri get uri => delegate.uri;
  @override
  bool get isAbsolute => delegate.isAbsolute;
  @override
  Directory get parent => delegate.parent;
  @override
  File get absolute => this;
  @override
  Future<bool> exists() => delegate.exists();
  @override
  bool existsSync() => delegate.existsSync();
  @override
  Future<FileStat> stat() => delegate.stat();
  @override
  FileStat statSync() => delegate.statSync();
  @override
  Future<int> length() async => (await stat()).size;
  @override
  int lengthSync() => statSync().size;
  // A provider's backing path may be inaccessible even while its FD is valid.
  @override
  Future<String> resolveSymbolicLinks() async => resolveSymbolicLinksSync();
  @override
  String resolveSymbolicLinksSync() =>
      '${delegate.absolute.path}#fd=$descriptor';

  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    var offset = start ?? 0;
    if (offset < 0 || (end != null && end < offset)) {
      throw RangeError('Invalid file range');
    }
    final fd = _DescriptorIo.duplicate(descriptor);
    if (fd < 0) throw FileSystemException('Original access expired', path);
    final buffer = _DescriptorIo.allocate(65536);
    if (buffer == nullptr) {
      _DescriptorIo.close(fd);
      throw const FileSystemException('Unable to allocate read buffer');
    }
    try {
      final stop = end ?? lengthSync();
      while (offset < stop) {
        final count = _DescriptorIo.read(
            fd, buffer, (stop - offset).clamp(0, 65536), offset);
        if (count < 0) {
          throw FileSystemException('Unable to read original', path);
        }
        if (count == 0) break;
        offset += count;
        yield Uint8List.fromList(buffer.asTypedList(count));
      }
    } finally {
      _DescriptorIo.release(buffer);
      _DescriptorIo.close(fd);
    }
  }

  @override
  Future<Uint8List> readAsBytes() async {
    final result = BytesBuilder(copy: false);
    await for (final chunk in openRead()) {
      result.add(chunk);
    }
    return result.takeBytes();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(await readAsBytes());
  @override
  Future<File> copy(String newPath) async {
    final target = File(newPath);
    final sink = target.openWrite();
    try {
      await sink.addStream(openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }
    return target;
  }

  // Unsupported operations include every mutation of the original file.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'Original book access is read-only: ${invocation.memberName}');
}
