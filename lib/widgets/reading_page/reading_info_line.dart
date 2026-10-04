import 'package:flutter/material.dart';

/// A metadata line has the same geometry regardless of which fields are shown
/// or whether the asynchronous battery value has arrived. Clip to that line so
/// icons cannot paint into the text below/above the reader chrome.
class ReadingInfoLine extends StatelessWidget {
  const ReadingInfoLine(
      {super.key, required this.style, required this.children});

  final TextStyle style;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final fontSize = style.fontSize ?? 10;
    final lineStyle = style.copyWith(height: 1.2);
    final height = MediaQuery.textScalerOf(context).scale(fontSize) * 1.2;
    return SizedBox(
      height: height,
      child: ClipRect(
        child: DefaultTextStyle.merge(
          style: lineStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final child in children) Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
