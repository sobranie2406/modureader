import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
const require = createRequire(`${process.env.MODU_JSDOM_ROOT ?? '/private/tmp/modu-119-js-tests'}/package.json`)
const { JSDOM } = require('jsdom')
const source = file => readFile(new URL(`../assets/foliate-js/src/${file}.js`, import.meta.url), 'utf8')
const data = text => `data:text/javascript;base64,${Buffer.from(text).toString('base64')}`
const analysis = data(await source('document-analysis'))
const { detectDocumentReadingMode: detect, imageEpubFromEvidence, resolveDocumentReadingMode } = await import(data(
    (await source('document-reading-mode')).replace("'./document-analysis.js'", JSON.stringify(analysis))))
const text = '<p>' + 'This is a text chapter, not a scanned image page. '.repeat(4) + '</p>'
const image = '<img src="page.png">'
const scanned = { kind: 'scanned', imageOnly: true, coverageUncertain: false }
const book = html => ({ resources: {}, sections: html.map((html, index) => ({
    id: `chapter-${index}`, createDocument: async () => new JSDOM(html).window.document,
})) })

test('PDF uses document menu regardless of text layer; other formats stay standard', async () => {
    assert.equal(await detect({ documentAnalysis: {}, readingRegionRenderer: {} }), 'pdf')
    assert.equal(await detect({ sections: [{ id: 'a' }], rendition: { layout: 'pre-paginated' } }), 'standard')
    assert.equal(await detect({ resources: {}, sections: [] }), 'standard')
})

test('text EPUB with cover/decorative images never creates image rendering source', async () => {
    const epub = book([image, text + image, text, text])
    epub.landmarks = [{ type: ['cover'], href: 'chapter-0' }]
    let created = 0
    assert.equal(await detect(epub, { createSource: () => { created++; throw Error('not needed') } }), 'standard')
    assert.equal(created, 0)
})

test('positive body geometry selects image EPUB, excludes cover/toc/nonlinear and preserves spine order', async () => {
    const epub = book([image, image, image, image, image, image])
    epub.sections[2].linear = 'no'
    epub.landmarks = [{ type: ['cover'], href: 'chapter-0' }, { type: ['toc'], href: 'chapter-4#contents' }]
    const inspected = []; let cleared = 0
    assert.equal(await detect(epub, { createSource: () => ({
        inspect: async index => { inspected.push(index); return scanned }, clear: () => cleared++,
    }) }), 'image-epub')
    assert.deepEqual(inspected, [1, 3, 5])
    assert.equal(cleared, 1)
})

test('isolated illustrations, uncertain coverage, fixed layout and mixed text do not imply image book', async () => {
    assert.equal(imageEpubFromEvidence([scanned, { kind: 'text' }, { kind: 'unknown' }]), false)
    assert.equal(imageEpubFromEvidence([{ ...scanned, coverageUncertain: true }]), false)
    assert.equal(imageEpubFromEvidence([{ ...scanned, imageOnly: false }]), false)
    assert.equal(imageEpubFromEvidence([{ ...scanned, excluded: true }]), false)
    assert.equal(imageEpubFromEvidence([scanned, scanned, { kind: 'text' }]), true)
    assert.equal(await detect(book([image]), { createSource: () => ({
        inspect: async () => ({ kind: 'image-candidate', imageOnly: false }), clear() {},
    }) }), 'standard')
})

test('at most five body sections are sampled, not the entire image EPUB', async () => {
    const inspected = []
    assert.equal(await detect(book(Array(100).fill(image)), { createSource: () => ({
        inspect: async index => { inspected.push(index); return scanned }, clear() {},
    }) }), 'image-epub')
    assert.deepEqual(inspected, [0, 25, 50, 74, 99])
})

test('inspection failure and deadline fail safely to original menu and release resources', async () => {
    let cleared = 0
    for (const inspect of [async () => { throw Error('broken image') }, () => new Promise(() => {})]) {
        assert.equal(await detect(book([image]), { timeoutMs: 30, createSource: () => ({
            inspect, clear: () => cleared++,
        }) }), 'standard')
    }
    assert.equal(cleared, 2)
    const controller = new AbortController(); controller.abort()
    let opened = false
    assert.equal(await detect(book([image]), { signal: controller.signal, createSource: () => {
        opened = true; throw Error('closed')
    } }), 'standard')
    assert.equal(opened, false)
})

test('reader startup only reads cached mode and never samples book sections', async () => {
    const epub = { resources: {}, get sections() { throw Error('opening must not sample') } }
    assert.equal(resolveDocumentReadingMode(epub, 'image-epub'), 'image-epub')
    assert.equal(resolveDocumentReadingMode(epub, null), 'standard')
    assert.equal(resolveDocumentReadingMode(epub, 'standard'), 'standard')
    assert.equal(resolveDocumentReadingMode({}, 'image-epub'), 'standard')
    const js = await source('book')
    const opening = js.slice(js.indexOf('  async open(file, cfi)'), js.indexOf('  setView(view)'))
    assert.doesNotMatch(opening, /detectDocumentReadingMode|analyzeEpubSection|\.inspect\(/)
    assert.match(opening, /resolveDocumentReadingMode\(this\.view\.book, settings\?\.mode\)/)
    assert.match(js, /if \(documentMode === 'image-epub'\) \{\s*if \(settings\?\.enabled\)/)
    assert.match(js, /inspectDocument \? detectDocumentReadingMode\(book\)/)
    assert.match(js, /documentReadingMode: await documentMode/)
    assert.match(js, /getMetadata\(await loadBook\(file\), urlParams.get\('inspectDocumentOnImport'\) === 'true'\)/)
})

for (const format of ['mobi', 'azw3', 'fb2']) test(`${format}: import detects images without EPUB resources, text remains standard`, async () => {
    const images = book(Array(8).fill(image)); delete images.resources
    images.imageDocumentSource = true
    images.sections.forEach((s, i) => s.id = i)
    images.landmarks = [{type:['cover'],href:'filepos:0'}]
    images.resolveHref = () => ({index:0})
    const sampled = []
    assert.equal(await detect(images, {createSource: () => ({
        inspect: async index => {sampled.push(index); return scanned}, clear() {},
    })}), 'image-epub')
    assert.equal(sampled.length, 5)
    assert.ok(!sampled.includes(0), 'Kindle cover guide is excluded')
    assert.equal(resolveDocumentReadingMode(images, 'image-epub'), 'image-epub')
    assert.equal(resolveDocumentReadingMode(images, null), 'standard')
    images.sections = book([text, text, text]).sections
    assert.equal(await detect(images, {createSource: () => {throw Error('text must not render')}}), 'standard')
})

test('Kindle/FB2 resource leases use decoded local sections, never revoke reader-owned URLs', async () => {
    const mobi = await source('mobi'), fb2 = await source('fb2')
    assert.equal([...mobi.matchAll(/imageDocumentSource = true/g)].length, 2)
    assert.equal([...mobi.matchAll(/loadImageDocument: async \(\) => \(\{ src: await this.loadSection\(section\), release\(\) \{\} \}\)/g)].length, 2)
    assert.match(fb2, /loadImageDocument: async \(\) => \(\{src: await load\(\), release\(\) \{\}\}\)/)
})

test('MOBI6 recindex-only comic samples reach decoded inspection, including a blank tail', async () => {
    const comic = book(Array(254).fill('<img recindex="00192" width="900" height="1358">').concat('<a></a>'))
    delete comic.resources; comic.imageDocumentSource = true
    comic.sections.forEach((section,index) => section.id = index)
    comic.landmarks = [{type:['toc'],href:'filepos:123'}]
    comic.resolveHref = () => ({index:1})
    const inspected = []; let cleared = 0
    assert.equal(await detect(comic,{createSource:()=>({
        inspect:async index=>{inspected.push(index);return scanned},clear:()=>cleared++,
    })}), 'image-epub')
    assert.deepEqual(inspected,[0,64,128,191])
    assert.equal(cleared,1)
    for(const inspect of [async()=>({kind:'image-candidate',imageOnly:false}),async()=>{throw Error('missing record')}])
        assert.equal(await detect(comic,{createSource:()=>({inspect,clear(){}})}),'standard')
    comic.sections=book([text+'<img recindex="00192">',text,text]).sections
    assert.equal(await detect(comic,{createSource:()=>{throw Error('Text must not need inspection')}}),'standard')
})
