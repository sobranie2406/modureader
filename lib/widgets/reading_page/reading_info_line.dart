import 'package:flutter/material.dart';

/// A metadata line has the same geometry regardless of which fields are shown
/// or whether the asynchronous battery value has arrived. Clip to that line so
/// icons cannot paint into the text below/above the reader chrome.
class ReadingInfoLine extends StatelessWidget {
  const ReadingInfoLine(
      {super.key,
      required this.style,
      required this.children,
      this.titleSlots = const {}});

  final TextStyle style;
  final List<Widget> children;
  final Set<int> titleSlots;

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
          child: LayoutBuilder(
              builder: (context, constraints) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var i = 0; i < children.length; i++)
                        if (titleSlots.isEmpty)
                          Flexible(child: children[i])
                        else if (titleSlots.contains(i))
                          Expanded(
                            child: Padding(
                              padding: EdgeInsetsDirectional.only(
                                  start: i == 0 ? 0 : 4,
                                  end: i == children.length - 1 ? 0 : 4),
                              child: Align(
                                alignment: [
                                  AlignmentDirectional.centerStart,
                                  Alignment.center,
                                  AlignmentDirectional.centerEnd,
                                ][i],
                                child: children[i],
                              ),
                            ),
                          )
                        else
                          // Short metadata keeps its natural width; titles use the rest.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth:
                                    constraints.maxWidth / children.length),
                            child: children[i],
                          ),
                    ],
                  )),
        ),
      ),
    );
  }
}
