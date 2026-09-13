import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Follow new output only while the user remains at the bottom. Never restart
/// a scrolling animation for each token, or pull a user away from older text.
class AiChatScrollController extends ScrollController {
  bool _following = true;
  bool _scheduled = false;
  bool _disposed = false;

  bool handleNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is UserScrollNotification) {
      _following = notification.direction != ScrollDirection.forward &&
          notification.metrics.extentAfter <= 48;
    } else if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _following = false;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _following = notification.metrics.extentAfter <= 48 &&
          (notification.scrollDelta ?? 0) >= 0;
    }
    return false;
  }

  void followAfterLayout({bool force = false}) {
    if (_disposed) return;
    if (force) _following = true;
    if (!_following || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed ||
          !hasClients ||
          !_following ||
          position.isScrollingNotifier.value) {
        return;
      }
      jumpTo(position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
