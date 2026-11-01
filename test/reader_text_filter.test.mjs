import test from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {createRequire} from 'node:module'
const {JSDOM}=createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom')
const load=async name=>import(`data:text/javascript;base64,${Buffer.from(await readFile(new URL(`../assets/foliate-js/src/${name}`,import.meta.url))).toString('base64')}`)
const {applyTextFilters}=await load('text-filter.js')
const {TTS}=await load('tts.js')
const cfi=await load('epubcfi.js')
for(const mode of ['text','paragraph']) test(`filter ${mode}: preserves anchors, skips speech and restores original`,()=>{
 const dom=new JSDOM('<html><body><p>正文关注<strong>公众号</strong>后文。</p><p>保留文字。</p></body></html>')
 const doc=dom.window.document
 globalThis.document=doc;globalThis.NodeFilter=dom.window.NodeFilter;globalThis.Range=dom.window.Range
 const original=doc.body.innerHTML
 const node=doc.querySelectorAll('p')[1].firstChild
 const range=doc.createRange();range.setStart(node,0);range.setEnd(node,2)
 const anchor=cfi.fromRange(range)
 applyTextFilters(doc,[{filterMode:mode,pattern:'关注公众号',scope:'all'}])
 assert.deepEqual(cfi.fromRange(range),anchor)
 const tts=new TTS(doc,null,()=>null), speech=[]
 for(let text=tts.start();text!=null;text=tts.next())speech.push(text)
 assert.ok(!speech.join('').includes('关注'))
 assert.ok(speech.join('').includes('保留文字'))
 if(mode==='text')assert.ok(speech.join('').includes('后文'))
 else assert.ok(!speech.join('').includes('后文'))
 applyTextFilters(doc,[])
 // Empty inline style attributes are harmless; content and native nodes survive.
 assert.equal(doc.body.textContent,'正文关注公众号后文。保留文字。')
 assert.equal(doc.querySelector('p').style.display,'')
 assert.equal(doc.querySelector('p strong').textContent,'公众号')
 dom.window.close()
})
test('CFI inside a split text run keeps its original character offset',()=>{
 const dom=new JSDOM('<html><body><p>前文删除后文</p></body></html>'),doc=dom.window.document
 globalThis.NodeFilter=dom.window.NodeFilter
 let range=doc.createRange();range.setStart(doc.querySelector('p').firstChild,4);range.setEnd(doc.querySelector('p').firstChild,6)
 const expected=cfi.fromRange(range)
 applyTextFilters(doc,[{filterMode:'text',pattern:'删除'}])
 range=doc.createRange();range.setStart(doc.querySelector('p').lastChild.firstChild,0);range.setEnd(doc.querySelector('p').lastChild.firstChild,2)
 assert.deepEqual(cfi.fromRange(range),expected)
 dom.window.close()
})

test('XHTML chapters use HTML namespace wrappers and restore correctly',()=>{
 const dom=new JSDOM('<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><p>前文广告后文</p></body></html>',{contentType:'application/xhtml+xml'})
 const doc=dom.window.document
 applyTextFilters(doc,[{filterMode:'text',pattern:'广告'}])
 assert.equal(doc.querySelector('span[style]').style.display,'none')
 applyTextFilters(doc,[])
 assert.equal(doc.querySelector('p').childNodes.length,1)
 assert.equal(doc.querySelector('p').textContent,'前文广告后文')
 dom.window.close()
})

test('background chapter lookahead prepares text filters before constructing speech cursors',async()=>{
 const view=await readFile(new URL('../assets/foliate-js/src/view.js',import.meta.url),'utf8')
 const creation=view.slice(view.indexOf('#ttsDocument(index) {'),view.indexOf('discardTTSSection(index)'))
 assert.ok(creation.indexOf('this.prepareTtsDocument?.(doc)')>=0)
 assert.ok(creation.indexOf('this.prepareTtsDocument?.(doc)')<creation.indexOf('entry.doc = doc'))
})
