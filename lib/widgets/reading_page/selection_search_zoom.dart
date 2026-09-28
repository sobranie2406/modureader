/// Page-only scaling: does not affect the reader, popup controls, or enable a
/// JavaScript bridge. Use CSS zoom so both shrinking and enlargement work on
/// mobile WebViews as well as desktop (native pinch zoom cannot always shrink).
String selectionSearchZoomScript(int percent) => '''
(() => {
  const root = document.documentElement;
  if (!root) return;
  root.style.setProperty('zoom', '${percent.clamp(50, 200) / 100}', 'important');
  root.style.setProperty('-webkit-text-size-adjust', '100%', 'important');
  root.style.setProperty('text-size-adjust', '100%', 'important');
})();
''';
