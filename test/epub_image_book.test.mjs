import test from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {createRequire} from 'node:module'
const require = createRequire(`${process.env.MODU_JSDOM_ROOT ?? '/private/tmp/modu-119-js-tests'}/package.json`)
const {JSDOM} = require('jsdom')
const dom = new JSDOM('')
globalThis.DOMParser = dom.window.DOMParser
const uri = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`
const stub = uri(`export const createEpubImageSource = book => ({
 info:async()=>({width:650,height:904,imageOnly:book.testImagePage}),
 render:async()=>({blob:new Blob(['raster'])}),clear(){}
})`)
const code = await readFile(new URL('../assets/foliate-js/src/epub-image-book.js',import.meta.url),'utf8')
const {createEpubImageBook} = await import(uri(code.replace("'./epub-image-source.js'",JSON.stringify(stub))))

for (const imageOnly of [true,false]) test(`image adapter retains original nodes; image mode=${imageOnly}`,async()=>{
 const original = URL.createObjectURL(new Blob(['<html><body><div id="original"><img src="page.png"></div></body></html>'],{type:'text/html'}))
 let releases=0
 const adapter=createEpubImageBook({testImagePage:imageOnly,sections:[{loadImageDocument:async()=>({src:original,release:()=>releases++})}]})
 let rendered
 try {
  const url=await adapter.sections[0].load()
  rendered=new JSDOM(await (await fetch(url)).text())
  const doc=rendered.window.document,computed=element=>rendered.window.getComputedStyle(element)
  assert.ok(doc.querySelector('#original > img'),'original nodes/CFI paths remain intact')
  const img=doc.querySelector('[data-document-base]')
  if(imageOnly){
   assert.equal(computed(img).visibility,'visible')
   assert.equal(computed(doc.querySelector('#original img')).visibility,'hidden')
   Object.assign(img.style,{left:'65px',top:'90.4px',width:'520px',height:'723.2px'})
   assert.equal(computed(img).left,'65px')
   assert.equal(computed(img).top,'90.4px')
   assert.doesNotMatch(doc.querySelector('style').textContent,/inset:0!important/)
   const detail=doc.createElement('img');detail.dataset.documentDetail=''
   Object.assign(detail.style,{left:'65px',top:'90.4px',width:'520px',height:'723.2px'})
   doc.body.append(detail)
   assert.equal(computed(detail).visibility,'visible','zoom/resize details must not be hidden with original images')
   assert.equal(computed(detail).left,'65px')
  }else{
   assert.equal(img,null)
   assert.notEqual(computed(doc.querySelector('#original img')).visibility,'hidden')
   assert.equal(adapter.nativeTextPages.has(0),true)
  }
 }finally{adapter.disposeImageBook();rendered?.window.close();URL.revokeObjectURL(original)}
 assert.equal(releases,1)
})
test.after(()=>dom.window.close())
