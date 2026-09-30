import 'dart:convert';

/// Only seeds the source editor on the chosen official website. Never clicks
/// translation/subscription buttons, reads book context, or invokes app bridges.
String webTranslationPrefillScript({
  required String host,
  required String selector,
  required String text,
  Map<String, String> additionalEditors = const {},
}) =>
    '''
(() => {
  const editors = ${jsonEncode({host: selector, ...additionalEditors})};
  if (location.protocol !== 'https:' || !Object.prototype.hasOwnProperty.call(editors, location.hostname)) return;
  if (window.__moduTranslationSeedStarted) return;
  window.__moduTranslationSeedStarted = true;
  const source = ${jsonEncode(text)};
  let observer;
  let timeout;
  const stop = () => { observer?.disconnect(); clearTimeout(timeout); };
  const fill = () => {
    const editor = document.querySelector(editors[location.hostname]);
    if (!editor || !editor.isConnected || editor.getBoundingClientRect().width === 0) return false;
    const nativeInput = editor.tagName === 'TEXTAREA' || editor.tagName === 'INPUT';
    const content = nativeInput ? null : editor.cloneNode(true);
    // Slate's placeholder is real DOM text, not a restored user draft.
    content?.querySelectorAll('[data-slate-placeholder], [data-slate-zero-width]')
      .forEach(node => node.remove());
    // Do not overwrite a restored draft or anything the user has already typed.
    if ((nativeInput ? editor.value : content.textContent || '').trim()) return true;
    if (nativeInput) {
      // Use the browser setter so React/Vue-controlled mobile editors receive
      // the input event too. Do not focus: opening the keyboard hides results.
      const prototype = editor.tagName === 'TEXTAREA'
        ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(prototype, 'value').set.call(editor, source);
      editor.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText', data: source}));
      return true;
    }
    editor.focus();
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(editor);
    selection.removeAllRanges();
    selection.addRange(range);
    // Slate handles beforeinput by updating its own model and cancelling the
    // browser edit. Avoid execCommand in that case, which would insert twice.
    const beforeInput = new InputEvent('beforeinput', {
      bubbles: true, cancelable: true, inputType: 'insertText', data: source
    });
    if (editor.dispatchEvent(beforeInput) === false) return true;
    document.execCommand('insertText', false, source);
    editor.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText', data: source}));
    return true;
  };
  if (fill()) return;
  observer = new MutationObserver(() => { if (fill()) stop(); });
  observer.observe(document.documentElement, {childList: true, subtree: true});
  timeout = setTimeout(stop, 20000);
})();
''';
