package com.modu.reader

import android.content.pm.PackageManager
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowInsets
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val readerKeys = ReaderPageKeys()
    private var pageKeyChannel: MethodChannel? = null
    private var readerKeysActive = false
    private var readerVolumeKeys = false
    private var refreshHostResumed = false

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val imeVisible = Build.VERSION.SDK_INT >= 30 &&
            window.decorView.rootWindowInsets?.isVisible(WindowInsets.Type.ime()) == true
        val result = readerKeys.handle(
            event.keyCode, event.action, event.repeatCount, event.deviceId,
            readerKeysActive && hasWindowFocus() && !imeVisible,
            readerVolumeKeys,
            (if (event.isCtrlPressed) 1 else 0) or (if (event.isShiftPressed) 2 else 0) or
                (if (event.isAltPressed) 4 else 0) or (if (event.isMetaPressed) 8 else 0),
        )
        if (result == -1 || result == 1) pageKeyChannel?.invokeMethod("turnPage", result)
        if (result in 3..7) pageKeyChannel?.invokeMethod("shortcut", result)
        // Do not also deliver handled keys to Flutter/WebView (double paging).
        return if (result != ReaderPageKeys.PASS) true else super.dispatchKeyEvent(event)
    }

    override fun onPause() {
        refreshHostResumed = false
        readerKeysActive = false
        readerKeys.reset()
        super.onPause()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // A Bluetooth HID can disappear without delivering key-up. Keep the
        // existing Flutter surface/engine and discard only the held-key latch.
        readerKeys.reset()
        refreshReaderHostState()
    }

    override fun onPostResume() {
        super.onPostResume()
        refreshHostResumed = true
        // onPause disables native interception, even if Dart's cached state
        // did not change. Ask the current reader to resend its route policy.
        refreshReaderHostState()
    }

    private fun refreshReaderHostState() {
        window.decorView.post {
            if (!isFinishing && !isDestroyed) {
                pageKeyChannel?.invokeMethod("hostStateChanged", null)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Flutter's built-in long-press/selection feedback uses DecorView.
        // Removing VIBRATE permission alone does not disable this API.
        window.decorView.isHapticFeedbackEnabled = false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Ensure the latest intent is stored so plugins relying on Activity#getIntent can read it.
        setIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val einkRefresh = EinkRefresh(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.modu.reader/eink_refresh").setMethodCallHandler { call, result ->
            when (call.method) {
                "supported" -> result.success(einkRefresh.supported())
                "refresh" -> result.success(
                    refreshHostResumed && hasWindowFocus() && !isFinishing &&
                        !isDestroyed && einkRefresh.request())
                else -> result.notImplemented()
            }
        }
        readerKeysActive = false
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.modu.reader/word_selection").setMethodCallHandler { call, result ->
            if (call.method != "bounds") {
                result.notImplemented()
            } else {
                try {
                    result.success(ReaderWordSelection.bounds(
                        call.argument<String>("text"),
                        call.argument<Number>("offset")?.toInt(),
                        call.argument<String>("locale"),
                    ))
                } catch (_: RuntimeException) {
                    // Never log book text or interrupt reading on a platform failure.
                    result.success(null)
                }
            }
        }
        pageKeyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.modu.reader/page_keys").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "configure") {
                    readerKeysActive = call.argument<Boolean>("active") == true
                    readerVolumeKeys = call.argument<Boolean>("volume") == true
                    readerKeys.configure(call.argument<List<Map<String, Number>>>("shortcuts"))
                    result.success(null)
                } else result.notImplemented()
            }
        }
        // A per-window override needs no WRITE_SETTINGS permission and has no
        // effect on another app or on the system's saved brightness setting.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.modu.reader/brightness").setMethodCallHandler { call, result ->
            if (call.method != "setBrightness") {
                result.notImplemented()
            } else {
                val brightness = call.argument<Number>("brightness")?.toFloat()
                if (brightness != null && !brightness.isFinite()) {
                    result.error("INVALID_BRIGHTNESS", "Brightness must be finite", null)
                } else {
                    try {
                        val attributes = window.attributes
                        attributes.screenBrightness = brightness?.coerceIn(0.2f, 1f) ?: -1f
                        window.attributes = attributes
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("BRIGHTNESS_FAILED", e.message, null)
                    }
                }
            }
        }
        if (!flutterEngine.plugins.has(CrashDiagnosticsPlugin::class.java)) {
            flutterEngine.plugins.add(CrashDiagnosticsPlugin())
        }
        if (!flutterEngine.plugins.has(LocalEmbeddingPlugin::class.java)) {
            flutterEngine.plugins.add(LocalEmbeddingPlugin())
        }
        if (!flutterEngine.plugins.has(LocalOcrPlugin::class.java)) {
            flutterEngine.plugins.add(LocalOcrPlugin())
        }
        if (!flutterEngine.plugins.has(BookFolderPlugin::class.java)) {
            flutterEngine.plugins.add(BookFolderPlugin())
        }

        val updateInstaller = AppUpdateInstaller(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.modu.reader/app_update").setMethodCallHandler { call, result ->
            if (call.method == "install") {
                updateInstaller.install(call.argument<String>("path"), result)
            } else result.notImplemented()
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INSTALL_INFO_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstallInfo" -> {
                    try {
                        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(
                                packageName,
                                PackageManager.PackageInfoFlags.of(0),
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, 0)
                        }
                        result.success(
                            hashMapOf(
                                "firstInstallTime" to packageInfo.firstInstallTime,
                                "lastUpdateTime" to packageInfo.lastUpdateTime,
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("PACKAGE_INFO_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val INSTALL_INFO_CHANNEL = "com.modu.reader/install_info"
    }
}
