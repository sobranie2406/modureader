export function normalizeDocumentDisplay(value = {}) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new RangeError('Invalid document display options')
    const out = {border:false, separators:true, grayscale:false, hideWatermarks:false, tapPan:false,
        swipe:'horizontal', swipeMenu:false, autoSeconds:0, ...value}
    if (['border','separators','grayscale','hideWatermarks','tapPan','swipeMenu'].some(k=>typeof out[k]!=='boolean') ||
        !['horizontal','reverse','vertical','tap'].includes(out.swipe) ||
        !Number.isInteger(out.autoSeconds) || out.autoSeconds < 0 || out.autoSeconds > 600 ||
        (out.autoSeconds > 0 && out.autoSeconds < 5)) throw new RangeError('Invalid document display options')
    if (out.swipe === 'vertical') out.swipeMenu = false
    return out
}

// One lifecycle per rendered document. Capture short single-finger gestures;
// leave long presses, handles, interactive controls and two-finger pan alone.
export function attachDocumentGestures(doc, getView, turn, menu) {
    let start, claimed = false, suppress = 0
    const consume = e => {e.preventDefault();e.stopImmediatePropagation()}
    doc.addEventListener('touchstart', e => {
        start = null; claimed = false
        const view = getView()
        if (view.mode === 'scroll' || e.touches.length !== 1 || doc.getSelection()?.type === 'Range' ||
            e.target.closest?.('a,button,input,textarea,select')) return
        start = {x:e.touches[0].screenX,y:e.touches[0].screenY,at:Date.now()}
    }, {capture:true,passive:true})
    doc.addEventListener('touchmove', e => {
        if (!start || e.touches.length !== 1 || Date.now()-start.at>350 || doc.getSelection()?.type==='Range') {start=null;return}
        const view = getView(), options = normalizeDocumentDisplay(view.display)
        const dx=e.touches[0].screenX-start.x,dy=e.touches[0].screenY-start.y
        if (Math.max(Math.abs(dx),Math.abs(dy))>12) {
            // Tap-only still consumes a swipe, so it cannot become a click.
            claimed = true; start.dx=dx;start.dy=dy;consume(e)
        }
    }, {capture:true,passive:false})
    doc.addEventListener('touchend', e => {
        if (!start || !claimed) return
        consume(e);suppress=Date.now()+450
        const view=getView(),o=normalizeDocumentDisplay(view.display),{dx=0,dy=0}=start
        start=null;claimed=false
        if (e.touches.length || doc.getSelection()?.type==='Range') return
        if (o.swipeMenu && view.zoom===1 && dy < -60 && Math.abs(dy)>Math.abs(dx)) menu()
        else if (o.swipe==='vertical' && Math.abs(dy)>60 && Math.abs(dy)>Math.abs(dx)) turn(dy<0?1:-1)
        else if (['horizontal','reverse'].includes(o.swipe) && Math.abs(dx)>60 && Math.abs(dx)>Math.abs(dy))
            turn((dx<0?1:-1)*(o.swipe==='reverse'?-1:1))
    }, {capture:true,passive:false})
    doc.addEventListener('touchcancel',()=>{start=null;claimed=false})
    doc.addEventListener('click',e=>{if(Date.now()<suppress)consume(e)},true)
}
