# AI and book indexes

Source-reviewed for Modu 1.2.3+10090 on 2026-10-08 ([b6bf820a](https://github.com/sobranie2406/modureader/tree/b6bf820a4a3fd5ee1f657c80c061f64349a1aedb)). Detailed workflows and current boundaries: [English](FEATURES.md) · [简体中文](FEATURES_zh.md). See the [documentation index](README.md) and [settings guide](SETTINGS.md).

The bookshelf book menu's **Vectorize / Re-vectorize** action is the shared manual indexing entry point. Automatic indexing uses the same background queue. The reading AI panel does not create a separate knowledge base or bypass the queue to write to the same index file concurrently. Vector model settings select the embedding model; AI settings select the language model that answers questions.

## Context used by each feature

| Use case | Source text and index |
| --- | --- |
| Free chat inside a book | Hybrid keyword/vector retrieval from the current book's valid index; snippets with identifiers are sent to the language model. |
| Book questions in home AI chat | The bookshelf tool first identifies the book ID, then the book-search tool preferentially searches that book's index. The model must support tool calling and the relevant tools must be enabled. |
| Chapter summary, concept explanation, argument analysis, excerpts, reading guide, vocabulary and mind map | Selected text or the current chapter's source text; no retrieved snippets from other chapters. |
| Smart translation | Selected text only. |
| Whole-book summary | Covers chapters through the table of contents, reusing valid indexed chapter text where available and extracting missing text through the reader. Content is compressed to the context budget; this is not a word-for-word reading of the entire book. |
| Character tracking | Reuses indexed text from already-read chapters and reads the current chapter only up to the current position. Stops if the reader cannot provide the read range, rather than substituting the entire chapter. |

## Index boundaries and fallback

- Query vectors must match the index's model, mode and dimensions. Re-vectorize after changing models.
- If a model is unavailable or incompatible, retrieval falls back to keywords instead of comparing vectors from different models.
- Home AI's search tool falls back to existing full-text search when no valid index or matching snippets are available. A damaged optional index does not block normal search.
- Home AI does not automatically treat the last-opened book as context or silently send the whole library to the language model.
- Retrieved snippets are sent as reference material to the selected AI service. With a remote embedding model, queries also go to that embedding service.
- Retrieval returns relevant snippets, not complete chapters or a whole-book summary. Each skill still observes its source scope and spoiler limits.
- Vector indexes remain local; WebDAV vector-index synchronization has been removed. Synchronizing vector-service configuration does not transfer index files.

## Reading skills and saved prompts

Open **Settings → AI reading skills** to manage skills and prompt overrides. Reading skills are visible by default; the visibility switch controls their initial display. **Edit skill templates before sending** is off by default, so tapping a template sends it immediately. When enabled, the template fills the input for editing before manual submission.

Built-in prompts follow the interface language unless a custom override has been saved. Only saved overrides are transferred with settings; built-in default text is not stored as a custom prompt. Restoring a default removes its override.

## Verification scope

Existing regression tests cover semantic matches without literal keyword matches, model-mismatch fallback, damaged/missing indexes, separation between books, actual search-tool integration and reading-skill context boundaries. This documentation update did not rerun them.

Implementation: [index service](../lib/service/knowledge/book_knowledge_index_service.dart), [index queue](../lib/service/knowledge/book_knowledge_index_queue.dart), [reading-skill execution](../lib/service/ai/reading_skill_execution.dart), [prompt store](../lib/service/ai/reading_skill_prompt_store.dart).
