import 'package:flutter/material.dart';
import 'package:modu_reader/widgets/common/app_scroll_behavior.dart';

/// Reserves a separate drag lane so the scrollbar cannot overlap controls.
class ReaderSettingsScrollView extends StatefulWidget {
  const ReaderSettingsScrollView({super.key, required this.child});
  final Widget child;

  @override
  State<ReaderSettingsScrollView> createState() =>
      _ReaderSettingsScrollViewState();
}

class _ReaderSettingsScrollViewState extends State<ReaderSettingsScrollView> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: AppScrollbar(
          controller: _controller,
          child: SingleChildScrollView(
            controller: _controller,
            primary: false,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ListTileTheme.merge(
              subtitleTextStyle: Theme.of(context).textTheme.bodySmall,
              child: widget.child,
            ),
          ),
        ),
      );
}
