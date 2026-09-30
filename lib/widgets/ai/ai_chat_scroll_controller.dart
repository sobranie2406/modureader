import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Follow new output only while the user remains at the bottom. Never restart
/// a scrolling animation for each token, or pull a user away from older text.
/// Once output finishes, reveal this reply's beginning for reading.
class AiChatScrollController extends ScrollController {
  bool _following = true;
  bool _scheduled = false;
  bool _disposed = false;
  int _completionGeneration = 0;

  bool handleNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _completionGeneration++;
      }
      _following = notification.direction != ScrollDirection.forward &&
          notification.metrics.extentAfter <= 48;
    } else if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _completionGeneration++;
      _following = false;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _following = notification.metrics.extentAfter <= 48 &&
          (notification.scrollDelta ?? 0) >= 0;
    }
    return false;
  }

  bool handleMetricsNotification(ScrollMetricsNotification notification) {
    // A lazy list's estimated extent can change after revealing a long reply.
    if (notification.depth == 0) followAfterLayout();
    return false;
  }

  void stopFollowing() {
    _following = false;
    _completionGeneration++;
  }

  void followAfterLayout({bool force = false}) {
    if (_disposed) return;
    if (force) {
      _completionGeneration++;
      _following = true;
    }
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
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void returnToReplyStartAfterLayout(GlobalKey replyStartKey) {
    if (_disposed || !_following) return;
    // Invalidate any token-follow callback already queued for this frame.
    _following = false;
    final generation = ++_completionGeneration;

    void revealAfterLayout(int remainingLayouts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed ||
            generation != _completionGeneration ||
            !hasClients ||
            position.isScrollingNotifier.value) {
          return;
        }
        final target = replyStartKey.currentContext?.findRenderObject();
        if (target == null || !target.attached) {
          // A fast response may finish before the lazy list builds its item.
          // Reveal the end first, then resolve the actual paragraph next frame.
          if (remainingLayouts > 0) {
            jumpTo(position.maxScrollExtent);
            revealAfterLayout(remainingLayouts - 1);
          }
          return;
        }
        final viewport = RenderAbstractViewport.maybeOf(target);
        if (viewport == null) return;
        final offset = viewport.getOffsetToReveal(target, 0).offset;
        jumpTo(offset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble());
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }

    revealAfterLayout(8);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
