import {
  FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult,
} from '@ohos/flutter_ohos';
import embedding from 'libmodu_embedding.so';

export default class LocalEmbeddingPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  // One native CPU session; serialize owners as well as load/embed/close.
  private static pending: Promise<void> = Promise.resolve();

  getUniqueClassName(): string { return 'ModuLocalEmbeddingPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'modu/ohos_embedding');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    LocalEmbeddingPlugin.pending = LocalEmbeddingPlugin.pending.then(() => embedding.close()).catch(() => {});
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'isAvailable') {
      result.success(embedding.isAvailable());
      return;
    }
    if (call.method !== 'load' && call.method !== 'embed' && call.method !== 'close') {
      result.notImplemented();
      return;
    }
    const channel = this.channel;
    LocalEmbeddingPlugin.pending = LocalEmbeddingPlugin.pending.then(async () => {
      if (channel === null || this.channel !== channel) return;
      try {
        const args: Map<string, Object> = call.args;
        if (call.method === 'load') {
          await embedding.load(args.get('modelPath') as string);
          if (this.channel === channel) result.success(null);
        } else if (call.method === 'embed') {
          const ids = args.get('ids') as BigInt64Array;
          const bytes = new Uint8Array(ids.buffer, ids.byteOffset, ids.byteLength);
          const vector = await embedding.embed(bytes, args.get('dimensions') as number);
          if (this.channel === channel) result.success(vector);
        } else {
          await embedding.close();
          if (this.channel === channel) result.success(null);
        }
      } catch (_) {
        if (this.channel === channel) {
          result.error('LOCAL_EMBEDDING_FAILED', '本地向量推理失败，请重试。', null);
        }
      }
    }).catch(() => {});
  }
}
