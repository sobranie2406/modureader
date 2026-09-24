// Do not expose or paginate the chapter with temporary fallback font metrics.
// The caller must treat a failed/timed-out font as a load failure, not display
// substitute text. Unused (unloaded) faces need not block the chapter.
export async function waitForReaderFonts(doc, timeout = 8000) {
  if (!doc.fonts) return true;
  doc.body?.getBoundingClientRect();
  let timer;
  try {
    return await Promise.race([
      // FontFaceSet.ready can resolve even when a requested face failed.
      doc.fonts.ready.then(() => !Array.from(doc.fonts).some(
        face => face.status === 'error' || face.status === 'loading'), () => false),
      new Promise(resolve => { timer = setTimeout(() => resolve(false), timeout); }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}
