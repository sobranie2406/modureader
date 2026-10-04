import 'package:flutter/material.dart';

/// Inherit the app theme, including its monochrome e-ink palette. Fixed-page
/// menus must not force black/white when the application uses a colored theme.
class DocumentPanelTheme extends StatelessWidget {
  const DocumentPanelTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Material(color: Theme.of(context).colorScheme.surface, child: child);
}

/// Aligned label column on tablets/desktops; stacked at phone widths or large
/// accessibility text sizes. No horizontal scrolling or fixed screenshot pixels.
class DocumentControlRow extends StatelessWidget {
  const DocumentControlRow(
      {super.key, required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: LayoutBuilder(builder: (context, constraints) {
          final title =
              Text(label, style: Theme.of(context).textTheme.titleSmall);
          if (constraints.maxWidth < 540 ||
              MediaQuery.textScalerOf(context).scale(14) > 20) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 4),
                  child,
                ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(width: 100, child: title),
            Expanded(child: child),
          ]);
        }),
      );
}
