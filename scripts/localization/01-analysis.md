# Localization maintenance analysis — Modu 1.2.0

Audience: everyday ebook readers. Follow the project's concise technical style.
Maintain UI translations in the languages listed in the current app catalog,
not only the project's default English documentation language. Preserve existing catalog
translations and user-defined names/prompts. New strings cover safe Android
storage startup, local dictionary import/error feedback, AI history/settings,
translation provider labels and bug report consent/privacy messages.

Use stable brace placeholders for dynamic values and substitute only after
translation. Preserve every placeholder, product name, identifier and URL.
Use the shared instructions in [02-prompt.md](02-prompt.md). The baseline is 1.2.0+10082 (2026-10-04), including scanned-book reading, crop, OCR models/reflow, online AI follow-up and Stop vectorization. Do not resurrect removed vector-index sync or standalone configuration QR entries. Assigned workers edit disjoint
catalog files only; the main agent owns code integration and verification.
