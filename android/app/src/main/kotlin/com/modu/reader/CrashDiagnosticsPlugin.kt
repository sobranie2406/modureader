package com.modu.reader

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream

/** Reads this app's system exit records only on explicit user request.
 * Raw tombstones stay in process memory and are allowlist-filtered by Dart;
 * no logcat, preferences, file paths or book contents are read.
 */
class CrashDiagnosticsPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        channel = MethodChannel(binding.binaryMessenger, "com.modu.reader/crash_diagnostics",
            StandardMethodCodec.INSTANCE, binding.binaryMessenger.makeBackgroundTaskQueue())
        channel!!.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "environment" -> {
                        val memory = ActivityManager.MemoryInfo()
                        manager.getMemoryInfo(memory)
                        @Suppress("DEPRECATION")
                        val version = context.packageManager.getPackageInfo(context.packageName, 0)
                        result.success(mapOf("android" to Build.VERSION.RELEASE,
                            "sdk" to Build.VERSION.SDK_INT, "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL, "abis" to Build.SUPPORTED_ABIS.toList(),
                            "ramMiB" to memory.totalMem / 1048576,
                            "version" to version.versionName,
                            "build" to (if (Build.VERSION.SDK_INT >= 28) version.longVersionCode else version.versionCode.toLong())))
                    }
                    "indexState" -> {
                        if (Build.VERSION.SDK_INT >= 30) {
                            val phase = (call.argument<Int>("phase") ?: 0).coerceIn(0, 7)
                            val done = (call.argument<Int>("done") ?: 0).coerceIn(0, 100000000)
                            val total = (call.argument<Int>("total") ?: 0).coerceIn(0, 100000000)
                            val model = (call.argument<Int>("model") ?: 0).coerceIn(0, 4)
                            @Suppress("DEPRECATION")
                            val version = context.packageManager.getPackageInfo(context.packageName, 0).longVersionCode
                            // OS limit: 128 bytes. No caller-supplied strings.
                            runCatching { manager.setProcessStateSummary(
                                "modu-index-v1|$version|$phase|$done|$total|$model".toByteArray(Charsets.US_ASCII)) }
                        }
                        result.success(null)
                    }
                    "read" -> {
                        if (Build.VERSION.SDK_INT < 30) {
                            result.success(mapOf("supported" to false))
                        } else {
                            val records = manager.getHistoricalProcessExitReasons(context.packageName, 0, 6)
                                .filter { it.reason in setOf(2, 3, 4, 5, 6, 7, 9) }.take(3)
                                .map { exit ->
                                    var trace: ByteArray? = null
                                    var traceStatus = "unavailable"
                                    if (Build.VERSION.SDK_INT >= 31 && exit.reason == ApplicationExitInfo.REASON_CRASH_NATIVE) {
                                        runCatching {
                                            exit.traceInputStream?.use { input ->
                                                val out = ByteArrayOutputStream()
                                                val buffer = ByteArray(8192)
                                                while (out.size() <= 1048576) {
                                                    val count = input.read(buffer)
                                                    if (count < 0) break
                                                    out.write(buffer, 0, count)
                                                }
                                                if (out.size() <= 1048576) {
                                                    trace = out.toByteArray()
                                                    traceStatus = "available"
                                                } else traceStatus = "too_large"
                                            }
                                        }.onFailure { traceStatus = "unreadable" }
                                    }
                                    mapOf("time" to exit.timestamp, "reason" to exit.reason,
                                        "status" to exit.status, "pss" to exit.pss, "rss" to exit.rss,
                                        "state" to exit.processStateSummary,
                                        "traceStatus" to traceStatus, "trace" to trace)
                                }
                            result.success(mapOf("supported" to true, "sdk" to Build.VERSION.SDK_INT,
                                "records" to records))
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: OutOfMemoryError) {
                result.error("CRASH_DIAGNOSTICS_UNAVAILABLE", "Insufficient memory to read diagnostics", null)
            } catch (error: Exception) {
                result.error("CRASH_DIAGNOSTICS_UNAVAILABLE", "System exit records unavailable", null)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
