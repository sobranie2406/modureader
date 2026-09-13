// The reader shell is trusted; EPUB documents are not. The native shell passes
// engine compatibility explicitly instead of guessing from a spoofable UA.
export const bookFrameSandbox = (search = globalThis.location?.search ?? '') => {
    let style = null
    try { style = JSON.parse(new URLSearchParams(search).get('style')) }
    catch { /* Invalid/missing policy fails closed. */ }
    const scripts = style?.allowScript === true || style?.readerScriptEvents === true
    // WebKit needs script permission even for parent-owned DOM event listeners:
    // https://bugs.webkit.org/show_bug.cgi?id=218086
    // This exception does NOT enable EPUB scripts: script_policy.js still removes
    // active content and adds script-src 'none' when allowScript is false.
    return scripts ? 'allow-same-origin allow-scripts' : 'allow-same-origin'
}
