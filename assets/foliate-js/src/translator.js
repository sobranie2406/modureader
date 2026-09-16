// Translation modes
export const TranslationMode = {
  OFF: 'off',
  TRANSLATION_ONLY: 'translation-only', 
  ORIGINAL_ONLY: 'original-only',
  BILINGUAL: 'bilingual'
}

// Make TranslationMode globally available for debugging
if (typeof window !== 'undefined') {
  window.TranslationMode = TranslationMode
}

// Translation function that calls Flutter's translation service
const translate = async (text, sessionId) => {
  try {
    // Call Flutter's translation handler
      return await window.flutter_inappwebview.callHandler('translateText', text, sessionId)
  } catch (error) {
    console.error('Translation failed:', error)
    return null
  }
}

export class Translator {
  #translationMode = TranslationMode.OFF
  observedElements = new Set()
  #translatedElements = new WeakMap()
  #observer = null
  #generation = 0
  #sessionId = null
  #queue = []
  #pending = new Set()
  #running = false
  #destroyed = false
  
  constructor() {
    this.#initializeObserver()
  }

  #initializeObserver() {
    this.#observer = new IntersectionObserver(
      (entries) => {
        // console.log(`IntersectionObserver triggered with ${entries.length} entries`)
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            // console.log('Element intersecting, translating:', entry.target.tagName, entry.target.textContent?.substring(0, 30))
            this.#enqueue(entry.target)
          }
        })
      },
      {
        rootMargin: '0px',
        threshold: 0
      }
    )
  }

  async setTranslationMode(mode, sessionId) {
    if (this.#destroyed) return
    if (!Object.values(TranslationMode).includes(mode)) {
      console.warn(`Invalid translation mode: ${mode}`)
      return
    }
    
    const oldMode = this.#translationMode
    this.#translationMode = mode
    this.#sessionId = sessionId
    if (mode === TranslationMode.OFF) {
      this.#generation++
      this.#queue = []
      this.#pending.clear()
    }
    
    if (oldMode !== mode) {
      // console.log(`Translation mode changed from ${oldMode} to ${mode}`)
      
      if (mode === TranslationMode.OFF) {
        // Turn off translation
        this.#updateTranslationDisplay()
      } else if (oldMode === TranslationMode.OFF) {
        // Turn on translation - force translate visible elements and wait for completion
        this.#updateTranslationDisplay()
        this.#forceTranslateVisibleElements()
      } else {
        // Just update display mode
        this.#updateTranslationDisplay()
      }
    }

    // Re-render annotations after translation mode change (and after translation completion)
    if (window.reader && window.reader.annotationsByValue) {
      const existingAnnotations = Array.from(window.reader.annotationsByValue.values())
      if (existingAnnotations.length > 0) {
        // console.log('Re-rendering annotations after translation mode change:', existingAnnotations.length)
        window.renderAnnotations(existingAnnotations)
      }
    }
  }

  getTranslationMode() {
    return this.#translationMode
  }

  observeDocument(doc) {
    // console.log('Observing document for translation, doc:', doc)
    if (!doc || this.#destroyed) {
      console.warn('No document provided to observeDocument')
      return
    }
        
    const textElements = this.#walkTextNodes(doc.body || doc.documentElement)
    // console.log(`Found ${textElements.length} text elements to observe`)
    
    textElements.forEach(element => {
      if (!this.observedElements.has(element)) {
        this.#observer.observe(element)
        this.observedElements.add(element)
        // console.log('Added element to observer:', element.tagName, element.textContent?.substring(0, 50))
      }
    })
    
    // console.log(`Total observed elements: ${this.observedElements.size}`)
  }

  clearTranslations() {
    this.#generation++
    this.#queue = []
    this.#pending.clear()
    const previousElements = Array.from(this.observedElements)

    // Remove all translation elements and restore original content
    this.observedElements.forEach(element => {
      const translationElements = element.querySelectorAll('.translated-text')
      translationElements.forEach(trans => trans.remove())
      
      // Restore original text if hidden
      this.#restoreOriginalText(element)
    })
    
    // Clear observer
    this.#observer.disconnect()
    this.observedElements.clear()
    this.#translatedElements = new WeakMap()
    
    // Reinitialize observer

    // Keep observing the current chapter so a target-language or provider
    // change can immediately retranslate without waiting for navigation.
    previousElements.forEach(element => {
      if (!this.#destroyed && element?.isConnected) {
        this.#observer.observe(element)
        this.observedElements.add(element)
      }
    })
  }

  #walkTextNodes(root, rejectTags = ['pre', 'code', 'math', 'style', 'script']) {
    const elements = []
    
    const walk = (node, depth = 0) => {
      if (depth > 15) return
      
      const children = Array.from(node.children || [])
      for (const child of children) {
        if (rejectTags.includes(child.tagName.toLowerCase())) {
          continue
        }
        
        // Skip translation elements
        if (child.classList.contains('translated-text')) {
          continue
        }
        
        const hasDirectText = Array.from(child.childNodes).some(node => {
          if (node.nodeType === Node.TEXT_NODE && node.textContent?.trim()) {
            return true
          }
          if (node.nodeType === Node.ELEMENT_NODE && node.tagName === 'SPAN') {
            return true
          }
          return false
        })
        
        if (child.children.length === 0 && child.textContent?.trim()) {
          elements.push(child)
        } else if (hasDirectText && !child.querySelector(
          'p,div,section,article,blockquote,ul,ol,table,h1,h2,h3,h4,h5,h6')) {
          elements.push(child)
        } else if (child.children.length > 0) {
          walk(child, depth + 1)
        }
      }
    }
    
    walk(root)
    return elements
  }

  #isVisible(element) {
    if (!element.isConnected) return false
    let {top, bottom, left, right} = element.getBoundingClientRect()
    let owner = element.ownerDocument.defaultView
    // Chapter rectangles are iframe-local, not reader-window coordinates.
    while (owner && owner !== window) {
      const frame = owner.frameElement
      if (!frame?.isConnected) return false
      const rect = frame.getBoundingClientRect()
      const sx = frame.offsetWidth ? rect.width / frame.offsetWidth : 1
      const sy = frame.offsetHeight ? rect.height / frame.offsetHeight : 1
      top = rect.top + (top + frame.clientTop) * sy
      bottom = rect.top + (bottom + frame.clientTop) * sy
      left = rect.left + (left + frame.clientLeft) * sx
      right = rect.left + (right + frame.clientLeft) * sx
      owner = frame.ownerDocument.defaultView
    }
    return top < window.innerHeight && bottom > 0 &&
      left < window.innerWidth && right > 0
  }

  #enqueue(element) {
    if (this.#destroyed || this.#translationMode === TranslationMode.OFF ||
        this.#translatedElements.has(element) || this.#pending.has(element) ||
        !this.#isVisible(element)) return
    this.#pending.add(element)
    this.#queue.push({element, generation: this.#generation, sessionId: this.#sessionId})
    void this.#drain()
  }

  async #drain() {
    if (this.#running) return
    this.#running = true
    try {
      while (this.#queue.length && !this.#destroyed) {
        const job = this.#queue.shift()
        try {
          if (job.generation === this.#generation && this.#isVisible(job.element)) {
            await this.#translateElement(job.element, job.generation, job.sessionId)
          }
        } finally {
          if (job.generation === this.#generation) this.#pending.delete(job.element)
        }
      }
    } finally { this.#running = false }
  }

  async #translateElement(element, generation, sessionId) {
    if (this.#translationMode === TranslationMode.OFF) return
    if (this.#translatedElements.has(element)) return
    
    const text = element.innerText?.trim()
    if (!text) return
    
    try {
      const translatedText = await translate(text, sessionId)
      if (this.#destroyed || generation !== this.#generation ||
          this.#translationMode === TranslationMode.OFF || !element.isConnected ||
          typeof translatedText !== 'string' || !translatedText.trim()) return
      
      // Mark as translated to prevent re-processing
      this.#translatedElements.set(element, {
        originalText: text,
        translatedText: translatedText
      })
      
      this.#applyTranslation(element, translatedText)
    } catch (error) {
      console.warn('Translation failed:', error)
    }
  }

  #applyTranslation(element, translatedText) {
    // Remove existing translation if any
    const existingTranslation = element.querySelector('.translated-text')
    if (existingTranslation) {
      existingTranslation.remove()
    }
    
    // Create translation wrapper
    const wrapper = element.ownerDocument.createElement('span')
    wrapper.className = 'translated-text'
    wrapper.setAttribute('data-translation-mark', '1')
    wrapper.style.display = 'block'
    // wrapper.style.fontSize = '0.9em'
    // wrapper.style.color = '#666'
    // wrapper.style.fontStyle = 'italic'
    wrapper.style.marginTop = '0.2em'
    wrapper.textContent = translatedText
    
    // Apply based on current mode
    this.#updateElementDisplay(element, wrapper)
    
    element.appendChild(wrapper)
  }

  #updateElementDisplay(element, translationWrapper) {
    const data = this.#translatedElements.get(element)
    if (!data) return
    
    switch (this.#translationMode) {
      case TranslationMode.TRANSLATION_ONLY:
        this.#hideOriginalText(element)
        translationWrapper.style.display = 'block'
        break
        
      case TranslationMode.ORIGINAL_ONLY:
        this.#restoreOriginalText(element)
        translationWrapper.style.display = 'none'
        break
        
      case TranslationMode.BILINGUAL:
        this.#restoreOriginalText(element)
        translationWrapper.style.display = 'block'
        break
        
      case TranslationMode.OFF:
      default:
        this.#restoreOriginalText(element)
        translationWrapper.style.display = 'none'
        break
    }
  }

  #hideOriginalText(element) {
    // Use CSS to hide original content instead of removing DOM nodes
    if (!element.hasAttribute('data-original-visibility')) {
      element.setAttribute('data-original-visibility', 'hidden')
      
      // Hide all child nodes except translation elements using CSS
      Array.from(element.childNodes).forEach(node => {
        if (node.nodeType === Node.ELEMENT_NODE) {
          const el = node
          if (!el.classList || !el.classList.contains('translated-text')) {
            // Store and hide using CSS
            if (!el.hasAttribute('data-original-display')) {
              el.setAttribute('data-original-display', el.style.display || 'initial')
              el.style.display = 'none'
            }
          }
        } else if (node.nodeType === Node.TEXT_NODE) {
          // For text nodes, store content and make invisible
          if (!node.__originalContent) {
            node.__originalContent = node.textContent
            node.textContent = ''
          }
        }
      })
    }
    
    // Mark element as having hidden text
    element.classList.add('translation-source-hidden')
  }

  #restoreOriginalText(element) {
    // Restore visibility by reversing the hide operations
    if (element.hasAttribute('data-original-visibility')) {
      // Restore all child nodes
      Array.from(element.childNodes).forEach(node => {
        if (node.nodeType === Node.ELEMENT_NODE) {
          const el = node
          if (!el.classList || !el.classList.contains('translated-text')) {
            // Restore original display
            if (el.hasAttribute('data-original-display')) {
              const originalDisplay = el.getAttribute('data-original-display')
              el.style.display = originalDisplay === 'initial' ? '' : originalDisplay
              el.removeAttribute('data-original-display')
            }
          }
        } else if (node.nodeType === Node.TEXT_NODE) {
          // Restore text content
          if (node.__originalContent !== undefined) {
            node.textContent = node.__originalContent
            delete node.__originalContent
          }
        }
      })
      
      element.removeAttribute('data-original-visibility')
    }
    
    element.classList.remove('translation-source-hidden')
  }

  #forceTranslateVisibleElements() {
    this.observedElements.forEach(element => this.#enqueue(element))
  }

  #updateTranslationDisplay() {
    // console.log('Updating translation display for mode:', this.#translationMode, 'Elements:', this.observedElements.size)
    this.observedElements.forEach(element => {
      const translationWrapper = element.querySelector('.translated-text')
      if (translationWrapper) {
        // console.log('Updating display for element with translation:', element)
        this.#updateElementDisplay(element, translationWrapper)
      } else {
        // console.log('No translation wrapper found for element:', element)
      }
    })
  }

  destroy() {
    this.#destroyed = true
    this.#translationMode = TranslationMode.OFF
    this.clearTranslations()
    this.#observer = null
  }
}
