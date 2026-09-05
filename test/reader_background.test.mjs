import test from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {runInNewContext} from 'node:vm'

test('CSS background URLs quote spaces, parentheses and apostrophes', async () => {
  const source = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8')
  const getBackground = runInNewContext(source.slice(source.indexOf('const getBackground = (bgimgUrl)'), source.indexOf('const applyBackground =')) + '\ngetBackground')
  assert.equal(getBackground('none'), 'none')
  const url = 'http://127.0.0.1:1234/bgimg/local/a (day)\'s.jpg'
  assert.equal(getBackground(url), `url(${JSON.stringify(url)})`)
})

test('delayed style update reads current background, and bridge uses JSON escaping', async () => {
  const source = await readFile(new URL('../lib/page/book_player/epub_player.dart', import.meta.url), 'utf8')
  const method = source.slice(source.indexOf('  void changeStyle('), source.indexOf('  void changeBgimgEffect('))
  assert.ok(method.indexOf('final bgimgUrl') > method.indexOf('styleTimer = Timer'))
  assert.equal((source.match(/backgroundImage: \$\{jsonEncode\(bgimgUrl\)\}/g) ?? []).length, 2)
})
