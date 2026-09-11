// Force font discovery while the iframe is laid out but hidden, then wait for
// its actual faces before exposing text or anchoring the reading position.
export async function waitForReaderFonts(doc, timeout = 8000) {
  if (!doc.fonts) return true;
  doc.body?.getBoundingClientRect();
  let timer;
  try {
    return await Promise.race([
      doc.fonts.ready.then(() => true, () => false),
      new Promise(resolve => { timer = setTimeout(() => resolve(false), timeout); }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}
