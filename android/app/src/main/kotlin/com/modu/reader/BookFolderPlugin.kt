package com.modu.reader

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import org.json.JSONObject
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
    private var pickingFiles = false
    private var inPlace = false
    private var selectionRoot: Uri? = null
    private val acquiredRoots = mutableSetOf<Uri>()
    private val handles = linkedMapOf<String, ParcelFileDescriptor>()
    private val links get() = context.getSharedPreferences("moduLinkedBooksV1", Context.MODE_PRIVATE)

    private fun openLink(key: String, record: JSONObject): String {
        check(key.matches(Regex("file/linked-[a-zA-Z0-9-]+\\.(epub|pdf|mobi|azw3|fb2)")))
        val descriptor = context.contentResolver.openFileDescriptor(Uri.parse(record.getString("uri")), "r")
            ?: error("Original unavailable")
        try {
            // Reject pipe-only providers rather than silently copying the book.
            Os.lseek(descriptor.fileDescriptor, 0, OsConstants.SEEK_SET)
            val folder = File(context.cacheDir, "linked-book-access")
            folder.mkdirs()
            val target = File(folder, key.substringAfter('/'))
            target.delete()
            Os.symlink("/proc/self/fd/${descriptor.fd}", target.absolutePath)
            check(OsConstants.S_ISREG(Os.fstat(descriptor.fileDescriptor).st_mode))
            handles.put(key, descriptor)?.close()
            return target.absolutePath
        } catch (error: Exception) {
            descriptor.close()
            throw error
        }
    }
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
                pickingFiles = call.argument<Boolean>("files") == true
                inPlace = call.argument<Boolean>("inPlace") == true
                pending = result
                try {
                    activity.startActivityForResult(Intent(if (pickingFiles) Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        if (pickingFiles) {
                            type = "*/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        }
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        if (inPlace) addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }, REQUEST)
                } catch (_: Exception) {
                    pending = null
                    result.error("PICK_FAILED", "Unable to open folder picker", null)
                }
            }
            "link" -> worker.execute {
                try {
                    val entry = entries[call.argument<String>("id")] ?: error("Unknown selection")
                    val key = "file/linked-${UUID.randomUUID()}.${entry.second.substringAfterLast('.').lowercase()}"
                    val record = JSONObject().put("uri", entry.first.toString())
                        .put("root", (if (pickingFiles) entry.first else selectionRoot).toString())
                    val root = Uri.parse(record.getString("root"))
                    context.contentResolver.takePersistableUriPermission(root, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    acquiredRoots.add(root)
                    val path = openLink(key, record)
                    if (!links.edit().putString(key, record.toString()).commit()) {
                        handles.remove(key)?.close()
                        File(path).delete()
                        error("Unable to save access")
                    }
                    main.post { result.success(mapOf("key" to key, "path" to path)) }
                } catch (_: Exception) {
                    main.post { result.error("LINK_FAILED", "Original does not support persistent random access. Import a copy instead.", null) }
                }
            }
            "restoreLinks" -> worker.execute {
                val restored = mutableMapOf<String, String>()
                for ((key, value) in links.all) {
                    try { restored[key] = openLink(key, JSONObject(value as String)) } catch (_: Exception) { }
                }
                main.post { result.success(restored) }
            }
            "forgetLink" -> worker.execute {
                val key = call.argument<String>("key") ?: ""
                handles.remove(key)?.close()
                if (key.startsWith("file/linked-") && !key.contains("..")) {
                    File(context.cacheDir, "linked-book-access/${key.substringAfter('/')}").delete()
                }
                val previous = links.getString(key, null)
                links.edit().remove(key).commit()
                if (previous != null) {
                    val root = JSONObject(previous).optString("root")
                    val retained = links.all.values.any { JSONObject(it as String).optString("root") == root }
                    if (!retained) try {
                        context.contentResolver.releasePersistableUriPermission(Uri.parse(root), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } catch (_: Exception) { }
                }
                main.post { result.success(null) }
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
                for (root in acquiredRoots) {
                    val retained = links.all.values.any { JSONObject(it as String).optString("root") == root.toString() }
                    if (!retained) try {
                        context.contentResolver.releasePersistableUriPermission(root, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } catch (_: Exception) { }
                }
                acquiredRoots.clear()
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
        val tree = data?.data ?: data?.clipData?.getItemAt(0)?.uri
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return true
        }
        worker.execute {
            try {
                selectionRoot = tree
                val found = mutableListOf<Map<String, String>>()
                fun add(uri: Uri, name: String, label: String) {
                    if (name.contains('/') || name.contains('\\') || name.substringAfterLast('.', "").lowercase() !in extensions) return
                    val key = found.size.toString()
                    entries[key] = Pair(uri, name)
                    found.add(mapOf("id" to key, "name" to name, "label" to label))
                }
                if (pickingFiles) {
                    val uris = linkedSetOf<Uri>()
                    data?.data?.let { uris.add(it) }
                    data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
                    for (uri in uris) {
                        context.contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                            if (it.moveToFirst()) add(uri, it.getString(0), it.getString(0))
                        }
                    }
                    main.post { result.success(found) }
                    return@execute
                }
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
                                add(DocumentsContract.buildDocumentUriUsingTree(tree, childId), name, label)
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
        worker.execute { handles.values.forEach { it.close() }; handles.clear() }
        worker.shutdown()
    }
    companion object { private const val REQUEST = 48129 }
}
