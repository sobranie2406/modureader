// core-js covers JavaScript built-ins, but not Blob's newer Web APIs.
// Response reads the Blob directly; keep native methods whenever available.
for (const [name, read] of [['arrayBuffer', response => response.arrayBuffer()],
  ['text', response => response.text()], ['stream', response => response.body]]) {
  if (typeof Blob !== 'undefined' && typeof Blob.prototype[name] !== 'function') {
    Object.defineProperty(Blob.prototype, name, {
      configurable: true, writable: true,
      value() { return read(new Response(this)) },
    })
  }
}
