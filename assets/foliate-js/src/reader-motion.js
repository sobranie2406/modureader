// Only presentation changes; do not touch reading style preferences or timers.
export const reducedReaderMotionCSS = `
  *, *::before, *::after {
    animation: none !important;
    transition: none !important;
    scroll-behavior: auto !important;
    caret-color: transparent !important;
  }
`;

export function applyReaderMotion(doc, disabled) {
  let sheet = doc.getElementById('modu-reduced-motion');
  if (!disabled) { sheet?.remove(); return; }
  if (!sheet) {
    sheet = doc.createElement('style');
    sheet.id = 'modu-reduced-motion';
    (doc.head || doc.documentElement).append(sheet);
  }
  sheet.textContent = reducedReaderMotionCSS;
}
