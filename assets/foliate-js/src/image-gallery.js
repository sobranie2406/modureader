// Keep section/ordinal pairs, not every image's bytes or live resource URLs.
export class BookImageGallery {
  constructor(book, section, ordinal) {
    this.book = book
    this.section = section
    this.ordinal = ordinal
    this.closed = false
  }
  close() { this.closed = true }
  async index() {
    const entries = []
    let initialIndex = -1
    for (let section = 0; section < this.book.sections.length; section++) {
      if (this.closed) throw new Error('Gallery closed')
      const item = this.book.sections[section]
      if (!item.createDocument || !item.loadImageDocument) continue
      const doc = await item.createDocument()
      const images = doc.querySelectorAll('img')
      for (let ordinal = 0; ordinal < images.length; ordinal++) {
        if (section === this.section && ordinal === this.ordinal) initialIndex = entries.length
        entries.push({ section, ordinal })
      }
    }
    if (this.closed || initialIndex < 0) throw new Error('Image not in book index')
    this.entries = entries
    return { count: entries.length, initialIndex }
  }
  async image(index) {
    const entry = this.entries?.[index]
    if (this.closed || !entry) throw new Error('Invalid image index')
    const loaded = await this.book.sections[entry.section].loadImageDocument()
    try {
      if (this.closed) throw new Error('Gallery closed')
      const response = await fetch(loaded.src)
      const doc = new DOMParser().parseFromString(await response.text(), 'text/html')
      const image = doc.querySelectorAll('img')[entry.ordinal]
      const source = image?.getAttribute('src')
      // Book resources are local; do not fetch remote tracking images.
      if (!/^(blob:|data:image\/)/i.test(source ?? '')) throw new Error('Image is not a local book resource')
      const blob = await fetch(source).then(r => r.blob())
      if (this.closed) throw new Error('Gallery closed')
      return await imageDataUrl(blob)
    } finally { loaded.release() }
  }
}

export const imageDataUrl = blob => new Promise((resolve, reject) => {
  const reader = new FileReader()
  reader.onload = () => resolve(reader.result)
  reader.onerror = reject
  reader.readAsDataURL(blob)
})
