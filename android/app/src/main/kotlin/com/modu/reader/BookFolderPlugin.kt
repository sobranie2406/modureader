package com.modu.reader

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Uses SAF URIs throughout; scoped storage does not grant raw-path access. */
class BookFolderPlugin : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null
    private var extensions = emptySet<String>()
    private val entries = linkedMapOf<String, Pair<Uri, String>>()
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.modu.reader/book_folder")
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> {
                val activity = binding?.activity
                if (pending != null || activity == null) {
                    result.error("UNAVAILABLE", "Folder picker is not available", null)
                    return
                }
                entries.clear()
                extensions = (call.argument<List<String>>("extensions") ?: emptyList()).toSet()
                pending = result
                try {
                    activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }, REQUEST)
                } catch (_: Exception) {
                    pending = null
                    result.error("PICK_FAILED", "Unable to open folder picker", null)
                }
            }
            "copy" -> {
                val ids = call.argument<List<String>>("ids") ?: emptyList()
                worker.execute {
                    var session: File? = null
                    try {
                        session = File(context.cacheDir, "book-folder-${UUID.randomUUID()}")
                        check(session.mkdirs())
                        val paths = ids.mapIndexed { index, id ->
                            val entry = entries[id] ?: error("Unknown entry")
                            val dir = File(session, "$index")
                            check(dir.mkdirs())
                            val file = File(dir, File(entry.second).name)
                            context.contentResolver.openInputStream(entry.first).use { input ->
                                checkNotNull(input)
                                file.outputStream().use { output -> input.copyTo(output) }
                            }
                            file.absolutePath
                        }
                        main.post { result.success(paths) }
                    } catch (_: Exception) {
                        session?.deleteRecursively()
                        main.post { result.error("READ_FAILED", "Unable to copy selected books", null) }
                    }
                }
            }
            "release" -> worker.execute {
                entries.clear()
                main.post { result.success(null) }
            }
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val result = pending ?: return true
        pending = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return true
        }
        worker.execute {
            try {
                val found = mutableListOf<Map<String, String>>()
                val visited = mutableSetOf<String>()
                fun visit(id: String, prefix: String) {
                    if (!visited.add(id)) return
                    val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
                    val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE)
                    val cursor = context.contentResolver.query(uri, columns, null, null, null)
                        ?: error("Unable to enumerate folder")
                    cursor.use {
                        while (it.moveToNext()) {
                            val childId = it.getString(0)
                            val name = it.getString(1) ?: continue
                            if (name.startsWith(".") || name.contains('/') || name.contains('\\')) continue
                            val label = if (prefix.isEmpty()) name else "$prefix/$name"
                            if (it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                                visit(childId, label)
                            } else if (name.substringAfterLast('.', "").lowercase() in extensions) {
                                val key = found.size.toString()
                                entries[key] = Pair(DocumentsContract.buildDocumentUriUsingTree(tree, childId), name)
                                found.add(mapOf("id" to key, "name" to name, "label" to label))
                            }
                        }
                    }
                }
                visit(DocumentsContract.getTreeDocumentId(tree), "")
                main.post { result.success(found.sortedBy { it["label"]?.lowercase() }) }
            } catch (_: Exception) {
                entries.clear()
                main.post { result.error("READ_FAILED", "Unable to read selected folder", null) }
            }
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
    }
    override fun onDetachedFromActivityForConfigChanges() {
        binding?.removeActivityResultListener(this)
        binding = null
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
        pending?.success(null)
        pending = null
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }
    companion object { private const val REQUEST = 48129 }
}
