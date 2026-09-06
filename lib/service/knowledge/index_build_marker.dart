import 'dart:io';

/// An old valid snapshot may survive an interrupted rebuild. Keep it for
/// recovery, but never use it to label the interrupted rebuild as successful.
File indexBuildMarker(File index) => File('${index.path}.building');

Future<T> withIndexBuildMarker<T>(
    File index, Future<T> Function() build) async {
  final marker = indexBuildMarker(index);
  await marker.parent.create(recursive: true);
  await marker.writeAsString('index-build-in-progress-v1', flush: true);
  try {
    return await build();
  } finally {
    // A killed process cannot reach this. The marker then survives restart.
    if (await marker.exists()) await marker.delete();
  }
}
