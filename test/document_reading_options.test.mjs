import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const {JSDOM}=createRequire(`${process.env.MODU_JSDOM_ROOT || '/private/tmp/modu-119-js-tests'}/package.json`)('jsdom');
const source=await readFile(new URL('../assets/foliate-js/src/document-reading-options.js',import.meta.url),'utf8');
const {normalizeDocumentDisplay,attachDocumentGestures}=await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
test('document options reject corrupt preferences and enforce menu/vertical exclusivity',()=>{
  for(const value of [{autoSeconds:1},{autoSeconds:601},{autoSeconds:NaN},{swipe:'bad'},{border:1}])assert.throws(()=>normalizeDocumentDisplay(value));
  assert.equal(normalizeDocumentDisplay({swipe:'vertical',swipeMenu:true}).swipeMenu,false);
});
for(const [swipe,dx,dy,expected] of [['horizontal',-100,0,1],['reverse',-100,0,-1],['vertical',0,-100,1],['tap',-100,0,null]])
  test(`single-page ${swipe} swipe action, preserving long-press and scroll`,()=>{
    const dom=new JSDOM('<p>Original text</p>'),doc=dom.window.document,actions=[];
    let view={zoom:1,mode:'single',display:{swipe}};
    attachDocumentGestures(doc,()=>view,d=>actions.push(d),()=>actions.push('menu'));
    const fire=(type,x,y,count=1)=>{const e=new dom.window.Event(type,{bubbles:true,cancelable:true});
      Object.defineProperty(e,'touches',{value:type==='touchend'?[]:Array.from({length:count},()=>({screenX:x,screenY:y}))});
      doc.querySelector('p').dispatchEvent(e);return e};
    fire('touchstart',200,200);fire('touchmove',200+dx,200+dy);fire('touchend',200+dx,200+dy);
    assert.deepEqual(actions,expected===null?[]:[expected]);actions.length=0;
    view.mode='scroll';fire('touchstart',200,200);fire('touchmove',200+dx,200+dy);fire('touchend',200+dx,200+dy);
    assert.deepEqual(actions,[]);
    view.mode='single';fire('touchstart',200,200,2);fire('touchmove',200+dx,200+dy,2);fire('touchend',200+dx,200+dy);
    assert.deepEqual(actions,[]);dom.window.close();
  });
