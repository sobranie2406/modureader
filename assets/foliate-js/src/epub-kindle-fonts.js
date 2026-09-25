// Some Kindle-to-EPUB conversions extract fonts as FONT00000.ttf, etc.,
// but leave the original one-based, base-32 kindle:embed URLs in their CSS.
// Resolve only this recognizable layout, never an arbitrary manifest position.
// Unrecognized/missing resources must still fail rather than use another font.
export const createKindleFontResolver = manifest => {
    const groups = new Map()
    for (const item of manifest) {
        if (!/^(?:font\/|application\/(?:vnd\.ms-opentype|font-sfnt|(?:x-)?font-(?:ttf|truetype|otf|opentype))$)/i
            .test(item.mediaType ?? '')) continue
        const match = /^(.*\/)?FONT(\d{5})\.(?:ttf|otf)$/i.exec(item.href)
        if (!match) continue
        const directory = match[1] ?? ''
        const fonts = groups.get(directory) ?? []
        fonts.push({ index: Number(match[2]), item })
        groups.set(directory, fonts)
    }
    for (const [directory, fonts] of groups) {
        fonts.sort((a, b) => a.index - b.index)
        // Gaps or duplicate resource numbers make the mapping ambiguous.
        if (fonts.some((font, index) => font.index !== index)) groups.delete(directory)
    }
    return (url, base) => {
        const match = /^kindle:embed:([0-9a-v]+)(?:\?mime=(?:font\/[\w.+-]+|application\/(?:vnd\.ms-opentype|(?:x-)?font-[\w.+-]+)))?$/i.exec(url)
        if (!match) return null
        const index = parseInt(match[1], 32) - 1
        if (!Number.isSafeInteger(index) || index < 0) return null
        const directory = base.slice(0, base.lastIndexOf('/') + 1)
        return groups.get(directory)?.[index]?.item ?? null
    }
}
