// Only the consumer advances the cursor. Serialize WebView calls and invalidate
// queued work on stop; never recurse indefinitely at the last/empty chapter.
export class TtsNavigator {
    #tail = Promise.resolve()
    #generation = 0
    constructor(getView) { this.getView = getView }
    stop() { this.#generation++ }
    move(direction, { section = false, last = direction < 0 } = {}) {
        const generation = this.#generation
        const operation = async () => {
            if (generation !== this.#generation) return ''
            const view = this.getView()
            view.initTTS()
            if (!section) {
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
                await view.renderer.goTo({ index })
                if (generation !== this.#generation) return ''
                const after = view.renderer.getContents()[0]
                if (after.index !== index || after.doc === before.doc) {
                    throw new Error('TTS chapter navigation did not finish; retry from the current sentence')
                }
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
