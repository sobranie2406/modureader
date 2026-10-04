import test from 'node:test'
import assert from 'node:assert/strict'
import { extractPdfText } from '../assets/foliate-js/src/document-text-extraction.js'

const item = (str,x,y,width=100) => ({str,width,dir:'ltr',transform:[10,0,0,10,x,y]})
const pdf = items => ({numPages:2, getPage:async n => {
    assert.ok(n===1 || n===2)
    return {getViewport:()=>({width:200,height:200,transform:[1,0,0,-1,0,200]}),
        getTextContent:async()=>({items,styles:{}})}
}})
test('whole page preserves text and reading order, no OCR',async()=>{
    const result=await extractPdfText(pdf([item('下一行',20,80),item('第一页',20,150)]),{page:0})
    assert.equal(result.text,'第一页\n下一行')
    assert.equal(result.source,'text-layer')
})
test('selected region excludes other lines and clips horizontal runs',async()=>{
    const result=await extractPdfText(pdf([item('甲乙丙丁戊',20,150),item('下一行',20,50)]),
        {page:0,region:{x:.1,y:.1,width:.2,height:.3}})
    assert.equal(result.text,'甲乙')
})
test('empty scanned page requests OCR at the caller',async()=>{
    assert.equal((await extractPdfText(pdf([]),{page:0})).text,'')
})
test('rejects out of range pages and malformed selections',async()=>{
    await assert.rejects(extractPdfText(pdf([]),{page:2}),RangeError)
    await assert.rejects(extractPdfText(pdf([]),{page:0,region:{x:-1,y:0,width:1,height:1}}),RangeError)
})
test('requests exactly one page, not the entire document',async()=>{
    let calls=0
    const source=pdf([item('Only this page',10,80)])
    const get=source.getPage
    source.getPage=async n=>{calls++;assert.equal(n,2);return get(n)}
    await extractPdfText(source,{page:1})
    assert.equal(calls,1)
})
