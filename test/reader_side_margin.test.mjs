import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';

const source = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
const method = source.slice(source.indexOf('  #beforeRender('), source.indexOf('\n  render() {'))
  .replaceAll('this.#', 'this.').replace('#beforeRender(', 'layout(');
const Harness = runInNewContext(`class Harness {
  constructor(width, height) {
    this.width = width; this.height = height;
    this.attrs = {flow: 'scrolled', gap: '6%', 'column-threshold': '720px',
      'max-inline-size': '720px', 'max-column-count': '1',
      'top-margin': '20px', 'bottom-margin': '20px'};
    this.container = {style: {}, getBoundingClientRect: () => ({width: this.width, height: this.height})};
    this.top = {style: {}, classList: {toggle() {}},
      getPropertyValue: key => this.attrs[key.replace('--_', '')]};
  }
  applyBackground() {}
  getAttribute(key) {return this.attrs[key]}
  hasAttribute(key) {return key in this.attrs}
  setAttribute(key, value) {this.attrs[key] = value}
  ${method}
}; Harness`, {getComputedStyle: el => el,
  makeMarginals: count => Array.from({length: count}, () => ({children: [{}]}))});

for (const width of [390, 800, 1280, 1920]) {
  test(`scrolled body uses the available ${width}px viewport, including small margin changes`, () => {
    const reader = new Harness(width, 900);
    let previous = Infinity;
    for (const percent of [0, 1, 2, 6, 10, 20]) {
      reader.attrs.gap = `${percent}%`;
      const layout = reader.layout({vertical: false, rtl: false});
      assert.ok(Math.abs(layout.columnWidth + layout.gap * 2 - width) < 1e-8,
        `margin ${percent}: no extra auto-centered whitespace`);
      assert.ok(layout.columnWidth < previous, 'every slider step changes the body width');
      assert.ok(layout.columnWidth > 0);
      previous = layout.columnWidth;
    }
  });
}

test('rotation recomputes scrolled width; column threshold cannot cap horizontal scrolling', () => {
  const reader = new Harness(800, 1280);
  const portrait = reader.layout({vertical: false, rtl: false});
  reader.width = 1280; reader.height = 800;
  const landscape = reader.layout({vertical: false, rtl: true});
  assert.ok(landscape.columnWidth > portrait.columnWidth);
  reader.attrs['column-threshold'] = '400px';
  assert.equal(reader.layout({vertical: false, rtl: true}).columnWidth, landscape.columnWidth);
  reader.width = 800; reader.height = 1280;
  assert.equal(reader.layout({vertical: false, rtl: false}).columnWidth, portrait.columnWidth);
});

test('desktop scrolling margins remain adjustable without the mobile image-fit path', () => {
  for (const width of [1024, 1440, 2560]) {
    for (const continuous of [false, true]) {
      const reader = new Harness(width, 900);
      Object.assign(reader.attrs, {
        'desktop-page-input': 'true', 'mobile-touch-paging': 'false',
        'mobile-image-fit': 'false', 'continuous-scroll': String(continuous),
      });
      for (const percent of [0, 2, 6, 20]) {
        reader.attrs.gap = `${percent}%`;
        const layout = reader.layout({vertical: false, rtl: false});
        assert.ok(Math.abs(layout.columnWidth + 2 * layout.gap - width) < 1e-8);
        assert.equal(layout.mobileImageFit, undefined);
        assert.equal(reader.container.style.overflowY, 'auto',
          'desktop page input must not disable scrolling');
      }
    }
  }
});

test('paginated single, double and automatic columns keep their existing sizing', () => {
  const reader = new Harness(1600, 900);
  reader.attrs.flow = 'paginated';
  for (const columns of [0, 1, 2]) {
    reader.attrs['max-column-count'] = `${columns}`;
    const layout = reader.layout({vertical: false, rtl: false});
    assert.equal(layout.columnWidth, 1600 / (columns || 2) - layout.gap);
  }
});

test('vertical scrolling and footnote sizing keep their independent width policy', () => {
  const reader = new Harness(1280, 800);
  assert.equal(reader.layout({vertical: true, rtl: false}).columnWidth, 720);
  reader.attrs.footnote = '';
  for (const vertical of [false, true]) {
    assert.equal(reader.layout({vertical, rtl: false}).columnWidth, 720);
  }
});

test('scrolled view applies the calculated width to the body, not an additional fixed limit', () => {
  const method = source.slice(source.indexOf('  scrolled({'), source.indexOf('\n  columnize('))
    .replaceAll('this.#', 'this.');
  const View = runInNewContext(`class View {
    vertical = false; document = {documentElement: {}, body: {}};
    setImageSize() {} expand() {} ${method}
  }; View`, {setStylesImportant: (element, styles) => Object.assign(element, styles)});
  const reader = new Harness(1280, 800);
  const view = new View();
  for (const percent of [0, 6, 20, 0]) {
    reader.attrs.gap = `${percent}%`;
    const layout = reader.layout({vertical: false, rtl: false});
    view.scrolled(layout);
    assert.equal(view.document.body['max-width'], `${layout.columnWidth}px`);
    assert.equal(view.document.documentElement.padding, `0 ${layout.gap}px`);
  }
});
