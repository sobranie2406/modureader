import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Page counters use ordinary Chinese numerals, not financial numerals.
String chinesePageNumber(int value, {bool traditional = false}) {
  if (value < 0) {
    return '负${chinesePageNumber(-value, traditional: traditional)}';
  }
  if (value == 0) return '零';
  const digits = '零一二三四五六七八九';
  String group(int n) {
    var result = '';
    var zero = false;
    for (var power = 3; power >= 0; power--) {
      final unit = math.pow(10, power).toInt();
      final digit = n ~/ unit;
      n %= unit;
      if (digit == 0) {
        if (result.isNotEmpty && n > 0) zero = true;
      } else {
        if (zero) result += '零';
        result += '${digits[digit]}${['', '十', '百', '千'][power]}';
        zero = false;
      }
    }
    return result;
  }

  final parts = <int>[];
  while (value > 0) {
    parts.add(value % 10000);
    value ~/= 10000;
  }
  var result = '';
  var skipped = false;
  final units = ['', traditional ? '萬' : '万', traditional ? '億' : '亿', '兆'];
  for (var i = parts.length - 1; i >= 0; i--) {
    final part = parts[i];
    if (part == 0) {
      skipped = true;
      continue;
    }
    if (result.isNotEmpty && (skipped || part < 1000)) result += '零';
    result += '${group(part)}${units[i]}';
    skipped = false;
  }
  return result.startsWith('一十') ? result.substring(1) : result;
}

class VerticalPageGeometry {
  const VerticalPageGeometry(
      this.safe, this.headerFontSize, this.footerFontSize);
  final EdgeInsets safe;
  final double headerFontSize, footerFontSize;
  double get left => safe.left + math.max(44, footerFontSize + 30);
  double get right => safe.right + math.max(44, headerFontSize + 30);
  double get top => safe.top + 18;
  double get bottom => safe.bottom + 18;
  Map<String, double> toJson() =>
      {'left': left, 'right': right, 'top': top, 'bottom': bottom};
}

class VerticalPageChrome extends StatelessWidget {
  const VerticalPageChrome(
      {super.key,
      required this.geometry,
      required this.chapterTitle,
      required this.remainingPages,
      required this.currentPage,
      required this.totalPages,
      required this.color,
      required this.redFrame});
  final VerticalPageGeometry geometry;
  final String chapterTitle;
  final int remainingPages, currentPage, totalPages;
  final Color color;
  final bool redFrame;

  /// macOS draws this chrome inside WKWebView. A full-window Flutter paint
  /// layer above a platform view can intercept native mouse events even when
  /// IgnorePointer excludes it from Flutter's own hit testing.
  Map<String, dynamic> toWebStyle(Locale locale) {
    final chinese = locale.languageCode == 'zh';
    final traditional = locale.scriptCode == 'Hant' ||
        ['TW', 'HK', 'MO'].contains(locale.countryCode);
    String number(int n) => chinese
        ? chinesePageNumber(math.max(0, n), traditional: traditional)
        : '$n';
    final remaining = chinese
        ? '本章${traditional ? '剩餘' : '剩余'}${number(remainingPages)}${traditional ? '頁' : '页'}'
        : '$remainingPages pages left';
    final progress = totalPages > 0
        ? '${number(currentPage.clamp(1, totalPages))}·${number(totalPages)}'
        : '';
    return {
      'title': chapterTitle,
      'remaining': remaining,
      'progress': progress,
      'chinese': chinese,
      'headerFontSize': geometry.headerFontSize,
      'footerFontSize': geometry.footerFontSize,
      'color':
          '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
      'opacity': color.a,
      'safe': {
        'left': geometry.safe.left,
        'right': geometry.safe.right,
        'top': geometry.safe.top,
        'bottom': geometry.safe.bottom,
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final labels = toWebStyle(Localizations.localeOf(context));
    final chinese = labels['chinese'] as bool;
    final remaining = labels['remaining'] as String;
    final progress = labels['progress'] as String;
    Widget column(String text, double fontSize,
            {bool chineseText = true,
            Alignment alignment = Alignment.topCenter}) =>
        LayoutBuilder(builder: (context, constraints) {
          final style =
              TextStyle(fontSize: fontSize, color: color, height: 1.1);
          if (!chineseText) {
            return Align(
                alignment: alignment,
                child: RotatedBox(
                    quarterTurns: 1,
                    child: Text(text,
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling)));
          }
          return Align(
              alignment: alignment,
              child: Text(text.characters.join('\n'),
                  semanticsLabel: text,
                  textAlign: TextAlign.center,
                  style: style,
                  textScaler: TextScaler.noScaling,
                  maxLines: math.max(
                      1, (constraints.maxHeight / (fontSize * 1.1)).floor()),
                  overflow: TextOverflow.ellipsis));
        });
    return IgnorePointer(
        child: SizedBox.expand(
            child: Stack(children: [
      if (redFrame)
        Positioned.fill(
            child: CustomPaint(
                key: const ValueKey('vertical-red-frame'),
                painter: _FramePainter(geometry))),
      Positioned(
          top: geometry.top + 8,
          bottom: geometry.bottom + 8,
          left: geometry.safe.left + 15,
          width: geometry.left - geometry.safe.left - 23,
          child: Column(children: [
            Expanded(
                child: Align(
                    alignment: Alignment.topCenter,
                    child: column(remaining, geometry.footerFontSize,
                        chineseText: chinese))),
            const SizedBox(height: 12),
            Expanded(
                child: Align(
                    alignment: Alignment.bottomCenter,
                    child: column(progress, geometry.footerFontSize,
                        chineseText: chinese,
                        alignment: Alignment.bottomCenter))),
          ])),
      Positioned(
          top: geometry.top + 8,
          bottom: geometry.bottom + 8,
          right: geometry.safe.right + 15,
          width: geometry.right - geometry.safe.right - 23,
          child: Align(
              alignment: Alignment.topCenter,
              child: column(chapterTitle, geometry.headerFontSize,
                  chineseText: chinese))),
    ])));
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter(this.geometry);
  final VerticalPageGeometry geometry;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
        geometry.safe.left + 8,
        geometry.safe.top + 8,
        size.width - geometry.safe.right - 8,
        size.height - geometry.safe.bottom - 8);
    if (rect.width <= 0 || rect.height <= 0) return;
    final paint = Paint()
      ..color = const Color(0xffc91c24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(rect, paint);
    paint.strokeWidth = 1;
    final inner = rect.deflate(5);
    canvas.drawRect(inner, paint);
    for (final x in [geometry.left - 5, size.width - geometry.right + 5]) {
      canvas.drawLine(Offset(x, inner.top), Offset(x, inner.bottom), paint);
    }
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) =>
      oldDelegate.geometry != geometry;
}
