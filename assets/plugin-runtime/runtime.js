/* Trusted host bootstrap. Plugin source is passed as data, never HTML. */
(() => {
  'use strict';
  let worker = null, workerUrl = null, count = 0, started = false, closed = false, ready = null;
  const stop = () => { closed=true; if(ready)window.removeEventListener('flutterInAppWebViewPlatformReady',ready); if (worker) worker.terminate(); worker = null; if(workerUrl) URL.revokeObjectURL(workerUrl); workerUrl=null; };
  window.moduPluginStop = stop;
  window.moduPluginStart = ({source, input, handler}) => {
    if (started || closed) return;
    const bridge = window.flutter_inappwebview;
    if (!bridge || typeof bridge.callHandler !== 'function') {
      if (!ready) {
        ready=()=>{ready=null;window.moduPluginStart({source,input,handler});};
        window.addEventListener('flutterInAppWebViewPlatformReady',ready,{once:true});
      }
      return;
    }
    started = true;
    const send = value => bridge.callHandler(handler, JSON.stringify(value));
    if (typeof Worker !== 'function' || typeof Blob !== 'function') {
      void send({kind:'error'}); return;
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
        library:Object.freeze({list:args=>request('library.list',args)}),
        notes:Object.freeze({save:args=>request('notes.save',args)}),
        articles:Object.freeze({capture:()=>request('articles.capture')}),
        privateLibrary:Object.freeze({open:()=>request('privateLibrary.open'),lock:()=>request('privateLibrary.lock')})
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
    try { worker = new Worker(url); } catch (_) { void send({kind:'error'}); return; }
    const current = worker;
    current.onerror = () => { if(worker===current){stop();void send({kind:'error'});} };
    current.onmessage = async event => {
      if (worker !== current) return;
      let json;
      try { json = JSON.stringify(event.data); } catch (_) { stop();void send({kind:'error'});return; }
      if (++count > 40 || typeof json !== 'string' || json.length > 65536) {
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
  };
})();
