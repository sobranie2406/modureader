import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
const method = source.slice(source.indexOf('  render() {'), source.indexOf('  get scrolled()'));
const Renderer = vm.runInNewContext(`class Renderer {
  #view; #continuous; #anchor = 'saved-position'; #preparingView = false; #destroyed = false;
  #sectionCache = {adopt(){}};
  continuousEnabled = false;
  restores = []; layouts = 0;
  constructor(continuous) {
    this.#view = {refreshDirection:()=>({}), render:()=>{this.layouts++;this.#view.onExpand()},
      onExpand:()=>this.scrollToAnchor(this.#anchor)};
    if(continuous) {
      const entry={index:0,src:'chapter',view:this.#view};
      this.#continuous={entries:new Map([[0,entry]]),pinned:0,current:entry,destroy(){}};
    }
  }
  #beforeRender(direction) {return direction}
  #afterScroll() {}
  #restoreExpandedAnchor() {this.scrollToAnchor(this.#anchor)}
  scrollToAnchor(anchor) {this.restores.push(anchor)}
  ${method}
}; Renderer`);
for (const continuous of [false,true]) test(`a layout restores its saved anchor once: exiting continuous=${continuous}`,()=>{
  const renderer = new Renderer(continuous);
  renderer.render();
  assert.equal(renderer.layouts,1);
  assert.deepEqual([...renderer.restores],['saved-position']);
});

test('single-chapter expansion compensates a live word range rather than rewinding to an old scroll position',()=>{
  const method=source.slice(source.indexOf('  #restoreExpandedAnchor() {'),source.indexOf('  get autoScrollSupported()'));
  const Reader=vm.runInNewContext(`class Reader {
    #view={document:{}};#vertical=false;#anchor;#anchorTop=100;#container={scrollTop:125};
    scrolled=true;top=100;fallback=0;
    constructor(){this.#anchor={startContainer:{ownerDocument:this.#view.document},getBoundingClientRect:()=>({top:this.top})}}
    #afterScroll(){}scrollToAnchor(){this.fallback++}
    expand(){this.#restoreExpandedAnchor()}get scroll(){return this.#container.scrollTop}
    ${method}
  };Reader`);
  const reader=new Reader();reader.top=300;reader.expand();
  assert.equal(reader.scroll,325);assert.equal(reader.fallback,0);
  reader.top=150;reader.expand();assert.equal(reader.scroll,175);
});
