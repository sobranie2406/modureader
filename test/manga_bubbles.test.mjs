import test from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
const source = await readFile(new URL('../assets/foliate-js/src/manga-bubbles.js', import.meta.url))
const {mangaReader} = await import('data:text/javascript;base64,'+source.toString('base64'))
const pause = ms => new Promise(resolve => setTimeout(resolve, ms))
const until = async (condition) => {
    for (let i=0; i<100 && !condition(); i++) await pause(15)
    assert.ok(condition())
}
const frame = (index, left) => ({index,doc:{
    querySelector: () => true, documentElement: {dataset:{}},
    defaultView:{frameElement:{parentElement:{getBoundingClientRect:()=>({
        width:300,height:400,left,top:0,right:left+300,bottom:400
    })}}}
}})
test('spread, recycled frames, blank pages and navigation during OCR',async () => {
    let frames = [frame(0,0),frame(1,300),frame(2,700)]
    const requests = [], draws = [], cancelled = []
    let release
    const reader = mangaReader({contents:()=>frames, viewport:()=>({width:600,height:500}),
        request: async p => {
            requests.push(p)
            if (p===0) return new Promise(resolve=>{release=resolve})
            return p===1 ? [] : [p]
        }, cancel:p=>cancelled.push(p),
        draw:(_,data)=>{ draws.push(data); return null }
    })
    reader.configure('read',1)
    await until(()=>requests.length===1)
    frames = [frame(1,0),frame(2,300)]
    reader.schedule()
    await until(()=>cancelled.length===1)
    release([0])
    await until(()=>draws.length===2)
    assert.deepEqual(requests,[0,1,2])
    assert.deepEqual(draws,[[],[2]])
    frames=[frame(2,0)]
    reader.schedule()
    await until(()=>draws.length===3)
    assert.deepEqual(requests,[0,1,2])
    reader.configure('off',2)
    reader.configure('translate',1)
    frames=[frame(3,0)]
    reader.schedule()
    await pause(100)
    assert.deepEqual(requests,[0,1,2])
})
