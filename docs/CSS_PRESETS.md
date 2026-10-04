# CSS profiles and regex highlight presets

## Current: Modu 1.2.0+10082

This guide describes the Modu publishing repository's `v1.2.0` commit `77dc238fb2ae2ce02455bd80c500ee9fd140f219`. Open Settings → CSS Settings to edit profiles; the reader selects which profiles apply.

## Using profiles

- Thirteen templates cover horizontal novels, vertical spacing, image fitting, centered headings, long-form spacing, English paragraphs, poetry, tables, dialogue color, wavy dialogue underlines, keyword highlights, date highlights and heading underlines.
- There are 32 named slots. Existing slots are retained; additional slots start with templates. Visual controls edit colors, fonts, spacing and underlines, alongside custom CSS.
- Selecting a profile only changes the editor's current slot. Enable both the profile and the main switch to apply it. Multiple profiles can be enabled; later slots take precedence when declarations conflict, subject to CSS specificity.
- A book can use its own enabled-profile combination or follow the default. Profile contents are shared globally, so editing affects every book using that profile. Per-book selection is not transferred between devices.
- Deletion requires confirmation, clears the slot and removes it from every book's enabled set. New, imported and copied profiles start disabled to prevent a reused slot affecting other books.
- The vertical template changes spacing; choose the book's reading direction separately in reading settings. Poetry classes, English language markers and other selectors depend on the book's structure and may need adjustment.

These controls style applicable book text and markup. PDF/scanned-page crop and image enhancement are separate display controls; OCR/reflow text uses its own document text-style editor. Ordinary text books retain their normal reading controls.

## File exchange

Import plain `.css` or Modu profile `.json` files up to 1 MiB. JSON preserves names, CSS, visual parameters, regex expressions and scope. Export the current profile or all nonempty profiles.

Import fills empty slots only and stops if there are too few; it does not overwrite automatically. Files contain no book IDs, font files or background images. Use trusted CSS: enabled remote-resource URLs can generate network requests.

Profiles and the default enabled set are also included in global settings backups, exchanged as settings files or `modu` links. Global settings no longer provide QR-code backups; files are recommended for complete backups.

## Regex highlighting

Enter a JavaScript regular expression without surrounding `/` characters; matching uses `gu` flags. Choose all text, headings (h1–h6/heading role) or body text. Matches do not cross paragraphs, but can span inline tags within a paragraph. Hidden content and content with EPUB/ARIA annotation semantics are skipped.

The code box takes CSS declarations rather than a full selector:

```css
color: #c0392b;
text-decoration-line: underline;
text-decoration-style: wavy;
text-decoration-color: #c0392b;
```

The CSS Custom Highlight API avoids splitting or wrapping body nodes, preserving annotation/CFI/narration positions. Highlight styling supports color, background color and underline style/color/thickness; it does not independently change fonts, font sizes or images inside a match. See the [Custom Highlight API styling limits](https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Custom_highlight_API).

The reading engine must support `CSS.highlights`, `Highlight` and Worker. Unsupported engines show a notice while ordinary CSS remains available. There is no fallback that wraps text in DOM nodes.

Regex matching runs in a separate Worker and stops after 1.2 seconds. Each chapter is limited to 500,000 characters, 20,000 text nodes and 2000 matches. Invalid expressions are skipped; timeouts and limits produce a notice. Disabling a profile removes its own highlights without clearing search highlights.

## Recorded development verification

The original implementation record reported:

- Flutter checks for configuration compatibility, multiple switches, global export, file validation, adding templates and narrow layouts.
- Reader checks for matching, Unicode empty matches, cancellation on timeout, hidden content, preserved text nodes and cleanup.
- Playwright checks using synthetic chapters for horizontal/vertical colors, wavy underlines, highlights, chapter changes, disabling/restoring and complex-regex timeouts. No private books were used or uploaded.

These are preserved historical results. No new application tests or browser checks were run for this documentation update.
