package com.modu.reader

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/** Phone inference has one owner, one background queue and bounded outputs. */
class LocalEmbeddingPlugin : FlutterPlugin {
    private val lock = Any()
    private val session = AndroidEmbeddingSession()
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.modu.reader/local_embedding",
            StandardMethodCodec.INSTANCE, binding.binaryMessenger.makeBackgroundTaskQueue())
        channel!!.setMethodCallHandler { call, result ->
            synchronized(lock) {
                try {
                    when (call.method) {
                        "load" -> {
                            session.load(requireNotNull(call.argument<String>("path")))
                            result.success(null)
                        }
                        "embed" -> {
                            val ids = requireNotNull(call.argument<LongArray>("ids"))
                            val dimension = requireNotNull(call.argument<Int>("dimensions"))
                            result.success(session.embed(ids, dimension))
                        }
                        "close" -> { session.close(); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (error: OutOfMemoryError) {
                    runCatching { session.close() }
                    result.error("LOCAL_EMBEDDING_MEMORY",
                        "本地向量化内存不足，已停止并释放模型。请关闭其他应用后重试。", null)
                } catch (error: Exception) {
                    runCatching { session.close() }
                    // No book content, file path or raw runtime dump in logs.
                    result.error("LOCAL_EMBEDDING_FAILED",
                        "本地向量推理失败，已释放模型，请重试。", null)
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        synchronized(lock) { runCatching { session.close() } }
        channel = null
    }
}
