import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const read = name => readFile(new URL(`../assets/foliate-js/src/${name}`, import.meta.url), 'utf8')
const source = await read('frame-script-policy.js')
const { bookFrameSandbox } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const search = style => `?${new URLSearchParams({style: JSON.stringify(style)})}`

test('missing, invalid and non-boolean policy cannot enable script permission', () => {
  for (const query of ['', '?style=broken', '?style=null', search({}), search({allowScript: 'true', readerScriptEvents: 1})]) {
    assert.equal(bookFrameSandbox(query), 'allow-same-origin')
  }
})
for (const allowScript of [false, true]) for (const readerScriptEvents of [false, true]) {
  test(`script opt-in=${allowScript}, WebKit event exception=${readerScriptEvents}`, () => {
    assert.equal(bookFrameSandbox(search({allowScript, readerScriptEvents})),
      allowScript || readerScriptEvents ? 'allow-same-origin allow-scripts' : 'allow-same-origin')
  })
}
test('paginator frame constructor applies policy before navigation', async () => {
  const paginator = await read('paginator.js')
  const viewClass = paginator.slice(paginator.indexOf('class View '), paginator.indexOf('\nexport class'))
  assert.ok(viewClass.includes("setAttribute('sandbox', bookFrameSandbox())"))
  assert.ok(!viewClass.includes("setAttribute('sandbox', 'allow-same-origin allow-scripts')"))
  const fixed = await read('fixed-layout.js')
  assert.ok(fixed.indexOf("setAttribute('sandbox', bookFrameSandbox())") < fixed.indexOf('iframe.src = src'))
})
test('native bridge explicitly scopes event workaround to WebKit platforms', async () => {
  const bridge = await readFile(new URL('../lib/utils/webView/gererate_url.dart', import.meta.url), 'utf8')
  assert.match(bridge, /'readerScriptEvents':\s*AnxPlatform.isMacOS \|\| AnxPlatform.isIOS \|\| AnxPlatform.isLinux/)
  const policy = await read('script_policy.js')
  assert.ok(!policy.includes('readerScriptEvents'))
  assert.ok(policy.includes("script-src 'none'"))
})
