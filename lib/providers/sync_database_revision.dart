import 'package:flutter_riverpod/flutter_riverpod.dart';

// A local invalidation signal, never a server clock or a new reading operation.
final syncDatabaseRevisionProvider = StateProvider<int>((ref) => 0);
