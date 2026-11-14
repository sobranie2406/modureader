import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modu_reader/service/private_library.dart';

final privateLibraryRevisionProvider = Provider<int>((ref) {
  final library = PrivateLibrary.instance;
  void changed() => ref.invalidateSelf();
  library.addListener(changed);
  ref.onDispose(() => library.removeListener(changed));
  return library.revision;
});
