import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source = name => readFile(new URL(`../assets/foliate-js/src/${name}.js`, import.meta.url), 'utf8');
const uri = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const G = await import(uri((await source('pdf-reading-viewport'))
    .replace("'./document-reading-options.js'", JSON.stringify(uri(await source('document-reading-options'))))
    .replace("'./document-regions.js'", JSON.stringify(uri(await source('document-regions'))))
    .replace("'./document-image-processing.js'", JSON.stringify(uri(await source('document-image-processing'))))));
const base = {pageWidth:600,pageHeight:800,width:390,height:700,crop:{x:.1,y:.1,width:.8,height:.8}};
const near = (a,b) => assert.ok(Math.abs(a-b)<1e-7, `${a} != ${b}`);

for (const rotation of [0,90,180,270]) test(`viewport matrix and visible ROI agree at ${rotation} degrees and 1500%`, () => {
    const p=G.pdfViewport({...base,view:{zoom:15,rotation},center:{x:.7,y:.3}});
    assert.ok(p.sourceRegion.width < .15 && p.sourceRegion.height < .15);
    const r=p.sourceRegion, [a,b,c,d,e,f]=p.matrix;
    const points=[[r.x,r.y],[r.x+r.width,r.y],[r.x,r.y+r.height],[r.x+r.width,r.y+r.height]]
        .map(([x,y])=>({x:a*x*600+c*y*800+e,y:b*x*600+d*y*800+f}));
    near(Math.min(...points.map(p=>p.x)),0);near(Math.min(...points.map(p=>p.y)),0);
    near(Math.max(...points.map(p=>p.x)),p.width);near(Math.max(...points.map(p=>p.y)),p.height);
});
test('fit width starts at top, panning clamps to crop and resize preserves source center', () => {
    const p=G.pdfViewport({...base,width:900,height:300,view:{fit:'width'}});
    near(p.sourceRegion.y,.1);near(p.width,900);
    assert.ok(p.sourceRegion.height < .8);
    const pan=G.panPdfViewport(p,0,100000);
    const bottom=G.pdfViewport({...base,width:900,height:300,view:{fit:'width'},center:pan});
    near(bottom.sourceRegion.y+bottom.sourceRegion.height,.9);
    const zoom=G.pdfViewport({...base,view:{zoom:5},center:{x:.5,y:.5}});
    const resized=G.pdfViewport({...base,width:1000,height:700,view:{zoom:5},center:zoom.center});
    near(resized.center.x,.5);near(resized.center.y,.5);
});
test('rotated wheel panning follows screen direction instead of original page axes', () => {
    const plan=G.pdfViewport({...base,view:{zoom:5,rotation:90},center:{x:.5,y:.5}});
    const center=G.panPdfViewport(plan,100,0);
    near(center.x,plan.center.x);assert.ok(center.y<plan.center.y);
});
test('invalid view parameters rejected and snapshots are isolated', () => {
    for(const view of [{zoom:0},{zoom:16},{zoom:NaN},{rotation:45},{fit:'invalid'}])
        assert.throws(()=>G.pdfViewport({...base,view}));
    assert.throws(()=>G.pdfViewport({...base,width:0}));
    assert.deepEqual(G.normalizePdfView({rotation:-90}),{zoom:1,fit:'screen',rotation:270,mode:'single'});
    assert.throws(()=>G.normalizePdfView({mode:'invalid'}));
});
test('selection toolbar uses all four transformed corners after a quarter turn', async () => {
    const book=await source('book');
    const body=book.slice(book.indexOf('const getPosition = '),book.indexOf('const getSelectionRange = '));
    const getPosition=new Function('window','getComputedStyle',body+'return getPosition;')(
        {innerWidth:800,innerHeight:600},()=>({transform:'matrix(0,2,-2,0,0,0)'}));
    const doc={defaultView:{frameElement:{getBoundingClientRect:()=>({left:0,top:0})}},
        pdfClientPoint:(x,y)=>({x:600-y*2,y:50+x*2})};
    const position=getPosition({getRootNode:()=>doc,
        getClientRects:()=>[{left:10,top:20,right:100,bottom:40}]});
    near(position.left,520/800);near(position.right,560/800);
    near(position.top,70/600);near(position.bottom,250/600);
});
