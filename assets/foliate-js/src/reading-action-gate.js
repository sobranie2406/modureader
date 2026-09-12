// WebView wake/resize can emit native scroll without the reader doing anything.
// Only a recent real input makes native scrolling a reading operation.
export class ReadingActionGate {
  #until = -1
  constructor(now = () => performance.now()) { this.now = now }
  input(event) {
    if (event.isTrusted) this.#until = this.now() + 3000
  }
  reset() { this.#until = -1 }
  isAction(reason) {
    if (reason === 'page' || reason === 'navigation') return true
    if ((reason === 'scroll' || reason === 'snap') && this.now() <= this.#until) {
      // Keep uninterrupted inertia alive, but never restart it after sleep.
      this.#until = this.now() + 3000
      return true
    }
    return false
  }
}
