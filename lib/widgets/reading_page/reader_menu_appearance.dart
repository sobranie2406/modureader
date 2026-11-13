import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:flutter/material.dart';

/// A captured menu theme also reaches dialogs and popup menus opened below it.
/// Only the outer surface paints opacity; content and controls keep their colors.
class ReaderMenuAppearance extends ThemeExtension<ReaderMenuAppearance> {
  const ReaderMenuAppearance(this.opacity);
  final double opacity;

  static bool translucent(BuildContext context) =>
      Theme.of(context).extension<ReaderMenuAppearance>() != null &&
      !Prefs().eInkMode;

  static Color background(BuildContext context, Color color) {
    final opacity =
        Prefs().eInkMode ? 1.0 : Prefs().readerMenuOpacityPercent / 100;
    return opacity == 1 ? color : color.withValues(alpha: opacity);
  }

  static ThemeData theme(BuildContext context) {
    final original = Theme.of(context);
    final base = original.copyWith(
      bottomSheetTheme: original.bottomSheetTheme
          .copyWith(modalBarrierColor: Colors.transparent),
      dialogTheme:
          original.dialogTheme.copyWith(barrierColor: Colors.transparent),
    );
    final opacity =
        Prefs().eInkMode ? 1.0 : Prefs().readerMenuOpacityPercent / 100;
    if (opacity == 1) return base;
    Color surface(Color? color) =>
        (color ?? base.colorScheme.surface).withValues(alpha: opacity);
    return base.copyWith(
      extensions: [
        ...base.extensions.values.where((e) => e is! ReaderMenuAppearance),
        ReaderMenuAppearance(opacity)
      ],
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: surface(base.canvasColor),
      cardTheme: base.cardTheme.copyWith(
          color: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.transparent),
      appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
          backgroundColor: surface(base.bottomSheetTheme.backgroundColor),
          modalBackgroundColor: surface(
              base.bottomSheetTheme.modalBackgroundColor ??
                  base.bottomSheetTheme.backgroundColor),
          elevation: 0,
          modalElevation: 0,
          surfaceTintColor: Colors.transparent),
      dialogTheme: base.dialogTheme.copyWith(
          backgroundColor: surface(base.dialogTheme.backgroundColor),
          elevation: 0,
          surfaceTintColor: Colors.transparent),
      popupMenuTheme: base.popupMenuTheme.copyWith(
          color: surface(base.popupMenuTheme.color),
          elevation: 0,
          surfaceTintColor: Colors.transparent),
    );
  }

  static Widget wrap(BuildContext context, Widget child) =>
      Theme(data: theme(context), child: child);

  @override
  ReaderMenuAppearance copyWith({double? opacity}) =>
      ReaderMenuAppearance(opacity ?? this.opacity);
  @override
  ReaderMenuAppearance lerp(covariant ReaderMenuAppearance? other, double t) =>
      ReaderMenuAppearance(
          opacity + ((other?.opacity ?? opacity) - opacity) * t);
}

Future<T?> showReaderDialog<T>(
    {required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    bool useRootNavigator = true,
    bool? requestFocus,
    Color? barrierColor,
    AnimationStyle? animationStyle}) {
  final menuTheme = ReaderMenuAppearance.theme(context);
  return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      requestFocus: requestFocus,
      barrierColor: Colors.transparent,
      animationStyle: animationStyle,
      builder: (_) => Theme(data: menuTheme, child: Builder(builder: builder)));
}
