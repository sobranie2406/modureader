/* Trusted host bootstrap. Plugin source is passed as data, never HTML. */
(() => {
  'use strict';
  let worker = null, workerUrl = null, count = 0, started = false, closed = false, ready = null, retry = null;
  const clearReadiness = () => {
    if (ready) window.removeEventListener('flutterInAppWebViewPlatformReady', ready);
    if (retry !== null) clearTimeout(retry);
    ready = null; retry = null;
  };
  const stop = () => { closed=true; clearReadiness(); if (worker) worker.terminate(); worker = null; if(workerUrl) URL.revokeObjectURL(workerUrl); workerUrl=null; };
  window.moduPluginStop = stop;
  window.moduPluginStart = ({source, input, handler, maxMessageBytes = 65536}) => {
    if (closed) return 'stopped';
    if (started) return 'running';
    const bridge = window.flutter_inappwebview;
    if (!bridge || typeof bridge.callHandler !== 'function') {
      if (!ready) {
        ready=()=>window.moduPluginStart({source,input,handler,maxMessageBytes});
        window.addEventListener('flutterInAppWebViewPlatformReady',ready,{once:true});
      }
      // Native startup can emit its ready event before callHandler is injected.
      // The host deadline owns this retry and calls stop on timeout/cancellation.
      if (retry === null) retry=setTimeout(()=>{retry=null;window.moduPluginStart({source,input,handler,maxMessageBytes});},50);
      return 'waiting_bridge';
    }
    clearReadiness();
    started = true;
    const messageLimit = maxMessageBytes === 4194304 ? 4194304 : 65536;
    const fitsMessage = text => {
      if (typeof text !== 'string' || text.length > messageLimit) return false;
      let bytes = 0;
      for (let i = 0; i < text.length; i++) {
        const code = text.charCodeAt(i);
        if (code < 128) bytes++;
        else if (code < 2048) bytes += 2;
        else if (code >= 0xd800 && code <= 0xdbff &&
            i + 1 < text.length && text.charCodeAt(i + 1) >= 0xdc00 &&
            text.charCodeAt(i + 1) <= 0xdfff) { bytes += 4; i++; }
        else bytes += 3;
        if (bytes > messageLimit) return false;
      }
      return true;
    };
    const send = value => bridge.callHandler(handler, JSON.stringify(value));
    if (typeof Worker !== 'function' || typeof Blob !== 'function') {
      void send({kind:'error'}); return 'unsupported_worker';
    }
    const prelude = `
      'use strict';
      const pending = new Map(); let next = 0;
      const post = self.postMessage.bind(self);
      const deny = () => { throw new Error('Use the host API'); };
      for (const key of ['fetch','XMLHttpRequest','WebSocket','EventSource','importScripts','Worker','SharedWorker','indexedDB','caches']) {
        Object.defineProperty(self,key,{value:deny,writable:false,configurable:false});
      }
      const request = (method,argumentsValue={}) => new Promise((resolve,reject) => {
        if (pending.size || ++next > 16) { reject(new Error('Plugin request limit')); return; }
        pending.set(next,{resolve,reject}); post({kind:'call',id:next,method,arguments:argumentsValue});
      });
      const modu = Object.freeze({
        http:Object.freeze({get:args=>request('http.get',args)}),
        library:Object.freeze({
          list:args=>request('library.list',args),
          tags:args=>request('library.tags',args),
          groups:args=>request('library.groups',args),
          tag:args=>request('library.tag',args),
          move:args=>request('library.move',args)
        }),
        books:Object.freeze({
          content:args=>request('books.content',args),
          chapter:args=>request('books.chapter',args)
        }),
        notes:Object.freeze({
          list:args=>request('notes.list',args),
          save:args=>request('notes.save',args)
        }),
        reading:Object.freeze({
          stats:args=>request('reading.stats',args),
          history:args=>request('reading.history',args)
        }),
        search:Object.freeze({library:args=>request('search.library',args)}),
        knowledge:Object.freeze({search:args=>request('knowledge.search',args)}),
        dictionary:Object.freeze({lookup:args=>request('dictionary.lookup',args)}),
        ai:Object.freeze({complete:args=>request('ai.complete',args)}),
        translate:Object.freeze({text:args=>request('translate.text',args)}),
        tts:Object.freeze({speak:args=>request('tts.speak',args)}),
        clipboard:Object.freeze({
          read:()=>request('clipboard.read'),
          write:args=>request('clipboard.write',args)
        }),
        share:Object.freeze({text:args=>request('share.text',args)}),
        ui:Object.freeze({
          confirm:args=>request('ui.confirm',args),
          prompt:args=>request('ui.prompt',args),
          select:args=>request('ui.select',args),
          progress:args=>request('ui.progress',args)
        }),
        open:Object.freeze({url:args=>request('open.url',args)}),
        storage:Object.freeze({
          list:()=>request('storage.list'),
          read:args=>request('storage.read',args),
          write:args=>request('storage.write',args),
          remove:args=>request('storage.remove',args)
        }),
        permissions:Object.freeze({
          request:args=>request('permissions.request',args),
          status:()=>request('permissions.status')
        }),
        articles:Object.freeze({capture:()=>request('articles.capture')}),
        privateLibrary:Object.freeze({
          open:()=>request('privateLibrary.open'),lock:()=>request('privateLibrary.lock'),
          state:()=>request('privateLibrary.state'),
          updateOptions:args=>request('privateLibrary.updateOptions',args),
          selectBooks:args=>request('privateLibrary.selectBooks',args),
          setPrivate:args=>request('privateLibrary.setPrivate',args)
        })
      });
      self.onmessage = async event => {
        const message = event.data;
        if (message.reply) {
          const task=pending.get(message.reply); if(!task)return;
          pending.delete(message.reply);
          if(message.error)task.reject(new Error('Plugin request failed'));else task.resolve(message.value);
          return;
        }
        if (!message.start) return;
        try {
          if (typeof window !== 'undefined' || typeof document !== 'undefined' || typeof flutter_inappwebview !== 'undefined') throw new Error('Unsupported runtime');
          const result = await (async (input, modu) => {
    `;
    const suffix = `
          })(message.input,modu);
          post({kind:'result',value:result});
        } catch (_) { post({kind:'error'}); }
      };
    `;
    const url = URL.createObjectURL(new Blob([prelude, source, suffix],{type:'application/javascript'}));
    workerUrl = url;
    try { worker = new Worker(url); } catch (_) { void send({kind:'error'}); return 'worker_error'; }
    const current = worker;
    current.onerror = () => { if(worker===current){stop();void send({kind:'error'});} };
    current.onmessage = async event => {
      if (worker !== current) return;
      let json;
      try { json = JSON.stringify(event.data); } catch (_) { stop();void send({kind:'error'});return; }
      if (++count > 40 || !fitsMessage(json)) {
        stop();void send({kind:'error'});return;
      }
      const message = event.data;
      if (message.kind === 'call') {
        try {
          const response = await bridge.callHandler(handler,json);
          if(worker===current)current.postMessage({reply:message.id,...response});
        } catch (_) { if(worker===current)current.postMessage({reply:message.id,error:true}); }
      } else {
        stop();void bridge.callHandler(handler,json);
      }
    };
    current.postMessage({start:true,input});
    return 'running';
  };
})();
