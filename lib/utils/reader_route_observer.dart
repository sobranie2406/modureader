import 'package:flutter/widgets.dart';

/// Popup menus / note editors remain part of reading. Full-screen page routes
/// (e.g. settings or book details) pause the reading-only sync timer.
final readerRouteObserver = RouteObserver<PageRoute<dynamic>>();
