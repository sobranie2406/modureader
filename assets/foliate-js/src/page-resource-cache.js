// Blob resources only; decoded canvases and PDF.js worker memory are separate.
export class PageResourceCache {
    constructor({maxEntries = 8, maxBytes = 24 * 1024 * 1024,
        release = resource => resource.urls.forEach(url => URL.revokeObjectURL(url))} = {}) {
        this.entries = new Map(); this.bytes = 0;
        this.maxEntries = maxEntries; this.maxBytes = maxBytes; this.release = release;
    }
    get(key) {
        const item = this.entries.get(key);
        if (item) { this.entries.delete(key); this.entries.set(key,item); }
        return item;
    }
    set(key, item) {
        this.delete(key); this.entries.set(key,item); this.bytes += item.bytes;
        // Keep the two most recently loaded pages: fixed-layout spreads load
        // both URLs before creating either iframe. Never revoke the left URL
        // while loading the right page. Canvas sizes are independently limited.
        while (this.entries.size > 2 &&
            (this.entries.size > this.maxEntries || this.bytes > this.maxBytes))
            this.delete(this.entries.keys().next().value);
    }
    delete(key) {
        const item = this.entries.get(key);
        if (!item) return;
        this.entries.delete(key); this.bytes -= item.bytes; this.release(item);
    }
    clear() { for (const key of [...this.entries.keys()]) this.delete(key); }
}

export function boundedRenderScale(width, height, requested, maxPixels = 4 * 1024 * 1024, maxSide = 4096) {
    if (![width,height,requested].every(n => Number.isFinite(n) && n > 0))
        throw new RangeError('Invalid PDF render dimensions');
    return Math.min(requested, Math.sqrt(maxPixels/(width*height)), maxSide/width, maxSide/height);
}
