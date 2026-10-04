package com.modu.reader

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.nio.FloatBuffer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/** One serialized background queue; no OCR work on Android's UI thread. */
class LocalOcrPlugin : FlutterPlugin {
    private val lock = Any()
    private val sessions = mutableMapOf<String, OrtSession>()
    private var channel: MethodChannel? = null
    private fun close() { sessions.values.forEach { runCatching { it.close() } }; sessions.clear() }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.modu.reader/local_ocr",
            StandardMethodCodec.INSTANCE, binding.binaryMessenger.makeBackgroundTaskQueue())
        channel!!.setMethodCallHandler { call, result -> synchronized(lock) {
            try {
                when (call.method) {
                    "load" -> {
                        close()
                        val path = requireNotNull(call.argument<String>("path"))
                        for (name in listOf("det", "rec")) {
                            OrtSession.SessionOptions().use { options ->
                                options.setIntraOpNumThreads(2); options.setInterOpNumThreads(1)
                                sessions[name] = OrtEnvironment.getEnvironment().createSession("$path/$name.onnx", options)
                            }
                        }
                        result.success(null)
                    }
                    "run" -> {
                        val session = requireNotNull(sessions[call.argument<String>("name")])
                        val data = requireNotNull(call.argument<FloatArray>("data"))
                        val shape = requireNotNull(call.argument<List<Number>>("shape")).map { it.toLong() }.toLongArray()
                        require(shape.size == 4 && shape[0] == 1L && shape[1] == 3L && data.size <= 3 * 1024 * 1024)
                        OnnxTensor.createTensor(OrtEnvironment.getEnvironment(), FloatBuffer.wrap(data), shape).use { input ->
                            session.run(mapOf(session.inputNames.first() to input)).use { outputs ->
                                val out = outputs[0] as OnnxTensor
                                val buffer = out.floatBuffer
                                require(buffer.remaining() <= 6000000)
                                val values = FloatArray(buffer.remaining()); buffer.get(values)
                                result.success(mapOf("data" to values, "shape" to out.info.shape.map { it.toInt() }))
                            }
                        }
                    }
                    "close" -> { close(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: OutOfMemoryError) {
                close(); result.error("OCR_MEMORY", "OCR memory limit reached", null)
            } catch (e: Exception) {
                close(); result.error("OCR_FAILED", "Local OCR failed", null)
            }
        } }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null); synchronized(lock) { close() }; channel = null
    }
}
