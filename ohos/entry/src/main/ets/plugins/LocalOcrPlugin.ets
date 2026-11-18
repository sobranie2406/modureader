import {
  FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult,
} from '@ohos/flutter_ohos';
import inference from 'libmodu_embedding.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

interface NativeOcrFailure {
  code?: string | number;
}

export default class LocalOcrPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private static pending: Promise<void> = Promise.resolve();

  getUniqueClassName(): string { return 'ModuLocalOcrPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'modu/ohos_ocr');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    LocalOcrPlugin.pending = LocalOcrPlugin.pending.then(() => inference.ocrClose()).catch(() => {});
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'load' && call.method !== 'run' && call.method !== 'close') {
      result.notImplemented();
      return;
    }
    const channel = this.channel;
    LocalOcrPlugin.pending = LocalOcrPlugin.pending.then(async () => {
      if (channel === null || this.channel !== channel) return;
      try {
        const args: Map<string, Object> = call.args;
        if (call.method === 'load') {
          await inference.ocrLoad(args.get('path') as string);
          if (this.channel === channel) result.success(null);
        } else if (call.method === 'run') {
          const input = args.get('data') as Float32Array;
          // OHOS NAPI can report float-array byte lengths as element counts.
          const bytes = new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
          const tensor = await inference.ocrRun(args.get('name') as string,
            bytes, args.get('shape') as number[]);
          const response: Map<string, Object> = new Map();
          response.set('data', new Float32Array(tensor.data));
          response.set('shape', tensor.shape);
          if (this.channel === channel) result.success(response);
        } else {
          await inference.ocrClose();
          if (this.channel === channel) result.success(null);
        }
      } catch (error) {
        const failure = error as NativeOcrFailure;
        const code = `${failure.code ?? 'UNKNOWN'}`;
        hilog.warn(0xD003900, 'ModuOCR', 'stage=%{public}s code=%{public}s',
          call.method, /^[A-Z0-9_]{1,80}$/.test(code) ? code : 'UNKNOWN');
        try { await inference.ocrClose(); } catch (_) {}
        if (this.channel === channel) result.error('OCR_FAILED', '本地文字识别失败，请重试。', null);
      }
    }).catch(() => {});
  }
}
