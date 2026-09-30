# Final localization audit

Audience: everyday ebook readers. Follow the project's concise technical style.
This final pass fills missing UI translations in all 15 supported languages, not
only the project's default English translation target. Preserve existing catalog
translations and user-defined names/prompts. New strings cover safe Android
storage startup, local dictionary import/error feedback, AI history/settings,
translation provider labels and bug report consent/privacy messages.

Use stable brace placeholders for dynamic values and substitute only after
translation. Preserve every placeholder, product name, identifier and URL.
Use the shared instructions in 02-prompt.md. Assigned workers edit disjoint
catalog files only; the main agent owns code integration and verification.
