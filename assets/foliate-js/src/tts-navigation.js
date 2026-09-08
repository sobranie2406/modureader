// Only the consumer advances the cursor. Serialize WebView calls and invalidate
// queued work on stop; never recurse indefinitely at the last/empty chapter.
export class TtsNavigator {
    #tail = Promise.resolve()
    #generation = 0
    constructor(getView, { navigationTimeoutMs = 5000, retryDelayMs = 50 } = {}) {
        this.getView = getView
        this.navigationTimeoutMs = navigationTimeoutMs
        this.retryDelayMs = retryDelayMs
    }
    stop() { this.#generation++ }
    start(range) { return this.move(1, { start: true, range }) }
    async #loadSection(view, index, before, generation) {
        const deadline = Date.now() + this.navigationTimeoutMs
        while (generation === this.#generation) {
            await view.renderer.goTo({ index })
            if (generation !== this.#generation) return false
            const after = view.renderer.getContents()[0]
            if (after?.index === index && after.doc && after.doc !== before.doc) return true
            // Paginator.goTo intentionally ignores navigation during a page
            // turn. Wait and retry the SAME chapter instead of pausing speech
            // or skipping its heading. A different destination is not ours.
            if (after?.index !== before.index || Date.now() >= deadline)
                throw new Error('TTS chapter navigation did not finish; retry from the current sentence')
            await new Promise(resolve => setTimeout(resolve, this.retryDelayMs))
        }
        return false
    }
    move(direction, { section = false, last = direction < 0, start = false, range } = {}) {
        const generation = this.#generation
        const operation = async () => {
            if (generation !== this.#generation) return ''
            const view = this.getView()
            view.initTTS()
            if (start) {
                const text = range ? view.tts.from(range) : view.tts.start()
                if (text?.trim()) return text
            } else if (!section) {
                const text = direction > 0 ? view.tts.next(true) : view.tts.prev(true)
                if (text?.trim()) return text
            }
            const sections = view.book.sections
            for (let attempts = 0; attempts < sections.length; attempts++) {
                if (generation !== this.#generation) return ''
                const before = view.renderer.getContents()[0]
                let index = before.index + direction
                while (index >= 0 && index < sections.length && sections[index].linear === 'no') index += direction
                if (index < 0 || index >= sections.length) return ''
                if (!await this.#loadSection(view, index, before, generation)) return ''
                view.initTTS()
                const text = last ? view.tts.end() : view.tts.start()
                if (text?.trim()) return text
            }
            return ''
        }
        const result = this.#tail.then(operation)
        this.#tail = result.catch(() => {})
        return result
    }
}
