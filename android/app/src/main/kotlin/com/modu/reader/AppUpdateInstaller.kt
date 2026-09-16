package com.modu.reader

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

// A dedicated, non-exported provider shares only the update cache, never books.
class ModuUpdateFileProvider : FileProvider()

class AppUpdateInstaller(private val activity: Activity) {
    private var busy = false

    fun install(path: String?, result: MethodChannel.Result) {
        if (busy) { result.error("BUSY", "Installer verification is busy", null); return }
        busy = true
        // APK parsing and signature verification must not block Flutter's UI.
        Thread {
            try {
                val root = File(activity.cacheDir, "modu-updates").canonicalFile
                val file = File(path ?: "").canonicalFile
                require(file.parentFile == root && file.isFile && file.name.endsWith(".apk"))
                val manager = activity.packageManager
                val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
                    else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
                @Suppress("DEPRECATION")
                val archive = manager.getPackageArchiveInfo(file.path, flags)
                    ?: error("Invalid package")
                @Suppress("DEPRECATION")
                val installed = manager.getPackageInfo(activity.packageName, flags)
                require(archive.packageName == activity.packageName)
                val newCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode
                    else @Suppress("DEPRECATION") archive.versionCode.toLong()
                val oldCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode
                    else @Suppress("DEPRECATION") installed.versionCode.toLong()
                require(newCode > oldCode) { "Package is not newer" }
                val oldSigners = signers(installed)
                require(oldSigners.isNotEmpty() && signers(archive) == oldSigners) {
                    "Package signing identity does not match"
                }
                activity.runOnUiThread {
                    try {
                        check(!activity.isDestroyed && !activity.isFinishing)
                        if (!manager.canRequestPackageInstalls()) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")))
                            result.success("permission_required")
                        } else {
                            val uri = FileProvider.getUriForFile(activity,
                                "${activity.packageName}.updates", file)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                clipData = ClipData.newRawUri("Modu update", uri)
                            }
                            activity.startActivity(intent)
                            result.success("opened")
                        }
                    } catch (_: Exception) {
                        result.error("INSTALL_FAILED", "Cannot open the system installer", null)
                    } finally { busy = false }
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    busy = false
                    result.error("INVALID_UPDATE", "Update package validation failed", null)
                }
            }
        }.start()
    }

    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners
            else @Suppress("DEPRECATION") info.signatures
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }?.toSet() ?: emptySet()
    }
}
