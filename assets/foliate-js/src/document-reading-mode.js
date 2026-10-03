import { analyzeEpubSection, samplePageIndices, checkCancelled } from './document-analysis.js'

// Menu routing is based on body evidence, never just an EPUB extension,
// fixed-layout metadata, cover art, or an old saved image-mode preference.
export function imageEpubFromEvidence(pages) {
    const body = pages.filter(page => !page.excluded)
    const images = body.filter(page => page.kind === 'scanned' &&
        page.imageOnly === true && page.coverageUncertain === false)
    return body.length > 0 && images.length / body.length >= .6
}

// Opening a book consumes import metadata only. This function must never read
// sections, create documents, decode images, or call the sampling detector.
export function resolveDocumentReadingMode(book, persistedMode) {
    if (book.documentAnalysis && book.readingRegionRenderer) return 'pdf'
    return book.resources && persistedMode === 'image-epub' ? 'image-epub' : 'standard'
}

export async function detectDocumentReadingMode(book, {
    signal, timeoutMs = 4000, createSource,
} = {}) {
    if (book.documentAnalysis && book.readingRegionRenderer) return 'pdf'
    if (!book.resources || !book.sections?.length) return 'standard'
    const controller = new AbortController()
    const abort = () => controller.abort()
    signal?.addEventListener('abort', abort, { once: true })
    if (signal?.aborted) abort()
    let source, timer
    const work = async () => {
        const active = controller.signal
        const body = book.sections.map((section, index) => ({ section, index }))
            .filter(({ section }) => section.linear !== 'no' && !book.landmarks?.some(item =>
                item.type?.some(type => ['cover', 'toc'].includes(type)) &&
                item.href?.split('#')[0] === section.id))
        const evidence = []
        for (const sample of samplePageIndices(body.length)) {
            checkCancelled(active)
            const { section, index } = body[sample]
            const doc = await section.createDocument?.()
            checkCancelled(active)
            let page = doc ? analyzeEpubSection(doc, { index, href: section.id }) : { kind: 'unknown' }
            if (page.images?.length && page.characters < 80) {
                if (!source) {
                    const factory = createSource ?? (await import('./epub-image-source.js')).createEpubImageSource
                    checkCancelled(active)
                    source = factory(book)
                }
                try { page = await source.inspect(index, { signal: active }) }
                catch (_) { checkCancelled(active) /* unsupported geometry is not positive evidence */ }
            }
            evidence.push(page)
        }
        return imageEpubFromEvidence(evidence) ? 'image-epub' : 'standard'
    }
    try {
        return await Promise.race([work(), new Promise(resolve => {
            timer = setTimeout(() => { abort(); resolve('standard') }, timeoutMs)
        })])
    } catch (_) {
        return 'standard'
    } finally {
        clearTimeout(timer)
        abort()
        source?.clear()
        signal?.removeEventListener('abort', abort)
    }
}
