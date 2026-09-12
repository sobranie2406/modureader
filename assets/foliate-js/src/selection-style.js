// Native selections can turn inactive when a Flutter overlay takes focus.
// Keep the book's temporary selection recognizable across platforms without
// clearing ranges or taking focus away from an editor. PDF owns a separate
// transparent text layer; do not override its foreground/line-break rules.
export function readerSelectionCSS({ pdf = false } = {}) {
  if (pdf) return '';
  return `
    ::selection {
      background-color: rgba(64, 156, 255, 0.35) !important;
      color: inherit !important;
      text-shadow: none !important;
    }
    ::selection:window-inactive {
      background-color: rgba(64, 156, 255, 0.35) !important;
      color: inherit !important;
      text-shadow: none !important;
    }
  `;
}
