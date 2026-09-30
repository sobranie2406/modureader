import { collapse, compare, isCFI } from './epubcfi.js'

// Match locations, not excerpt text: repeated sentences elsewhere in the book
// must never become deletion targets. Touching endpoints are not an overlap.
export function selectionAnnotationIds(cfi, annotations) {
  if (!isCFI.test(cfi)) return []
  let start, end
  try {
    start = collapse(cfi)
    end = collapse(cfi, true)
    if (compare(start, end) >= 0) return []
  } catch { return [] }
  const ids = new Set()
  for (const annotation of annotations) {
    if (!['highlight', 'underline'].includes(annotation.type)
      || !Number.isInteger(annotation.id) || annotation.id <= 0
      || !isCFI.test(annotation.value)) continue
    try {
      const markStart = collapse(annotation.value)
      const markEnd = collapse(annotation.value, true)
      if (compare(markStart, markEnd) < 0
        && compare(start, markEnd) < 0 && compare(markStart, end) < 0)
        ids.add(annotation.id)
    } catch { /* A broken old mark must not break normal text selection. */ }
  }
  return [...ids]
}
