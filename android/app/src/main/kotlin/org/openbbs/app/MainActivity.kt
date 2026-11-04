package org.openbbs.app

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 云盘下载落盘。
 *
 * 安卓写公共目录有两条道：
 * - 没选目录 → MediaStore 的「下载」集合，落在 Download/OpenBBS，任何文件管理器都看得见，
 *   不需要任何权限（API 29+）；API 28 及以下退回直接写公共 Download 目录。
 * - 用户选了目录 → SAF 拿到的树 URI，之后一直用 takePersistableUriPermission 记住，
 *   重启也在。内容写进去要过 ContentResolver，不能直接 File。
 *
 * 复制走子线程：几百 MB 的文件在方法通道线程上拷会把界面卡住。
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "openbbs/downloads"
        private const val REQ_DIR = 4801
        private const val FOLDER = "OpenBBS"
    }

    private var dirResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDir" -> pickDir(result)
                    "dirLabel" -> result.success(labelOf(call.argument<String>("uri")))
                    "save" -> save(
                        src = call.argument<String>("src") ?: "",
                        name = call.argument<String>("name") ?: "file",
                        mime = call.argument<String>("mime") ?: "application/octet-stream",
                        dirUri = call.argument<String>("dirUri"),
                        result = result,
                    )
                    "open" -> open(
                        uri = call.argument<String>("uri") ?: "",
                        path = call.argument<String>("path"),
                        mime = call.argument<String>("mime") ?: "*/*",
                        result = result,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    // ---------------------------------------------------------------- 选目录

    private fun pickDir(result: MethodChannel.Result) {
        dirResult?.success(null)
        dirResult = result
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        startActivityForResult(i, REQ_DIR)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_DIR) {
            val r = dirResult
            dirResult = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                r?.success(null)
                return
            }
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                // 有些系统的文件管理不给持久授权，那这次能用、下次会退回默认目录。
            }
            r?.success(mapOf("uri" to uri.toString(), "label" to labelOf(uri.toString())))
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** tree URI 里取出人能看懂的一段：primary:Download/OpenBBS → Download/OpenBBS。 */
    private fun labelOf(raw: String?): String? {
        if (raw.isNullOrEmpty()) return null
        return try {
            val id = DocumentsContract.getTreeDocumentId(Uri.parse(raw))
            val tail = id.substringAfter(':', id).trim('/')
            if (tail.isEmpty()) "内部存储" else tail
        } catch (_: Exception) {
            null
        }
    }

    // ---------------------------------------------------------------- 存

    private fun save(
        src: String,
        name: String,
        mime: String,
        dirUri: String?,
        result: MethodChannel.Result,
    ) {
        val file = File(src)
        if (!file.exists()) {
            result.error("missing", "临时文件不见了：$src", null)
            return
        }
        Thread {
            try {
                val saved =
                    if (!dirUri.isNullOrEmpty()) {
                        saveToTree(Uri.parse(dirUri), file, name, mime)
                    } else {
                        saveToDownloads(file, name, mime)
                    }
                runOnUiThread { result.success(saved) }
            } catch (e: Exception) {
                runOnUiThread { result.error("saveFailed", e.message ?: e.toString(), null) }
            }
        }.start()
    }

    /** 用户选过的目录（SAF）。同名文件不覆盖，自动加 (1)(2)。 */
    private fun saveToTree(
        tree: Uri,
        src: File,
        name: String,
        mime: String,
    ): Map<String, Any?> {
        val parentDocId = DocumentsContract.getTreeDocumentId(tree)
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, parentDocId)
        val finalName = uniqueName(tree, parentDocId, name)
        val doc = DocumentsContract.createDocument(contentResolver, parent, mime, finalName)
            ?: throw IllegalStateException("目录里建不了文件，可能没有写权限")
        contentResolver.openOutputStream(doc)?.use { out ->
            src.inputStream().use { it.copyTo(out, 64 * 1024) }
        } ?: throw IllegalStateException("写不进这个目录")
        val dirName = labelOf(tree.toString()) ?: ""
        val display = if (dirName.isEmpty()) finalName else "$dirName/$finalName"
        return mapOf("uri" to doc.toString(), "display" to display, "path" to null)
    }

    private fun uniqueName(tree: Uri, parentDocId: String, name: String): String {
        val taken = HashSet<String>()
        try {
            val childUri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentDocId)
            contentResolver.query(
                childUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null,
            )?.use { c ->
                while (c.moveToNext()) taken.add(c.getString(0) ?: "")
            }
        } catch (_: Exception) {
            return name
        }
        if (!taken.contains(name)) return name
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var n = 1
        while (taken.contains("$stem ($n)$ext")) n++
        return "$stem ($n)$ext"
    }

    /** 没选目录时的默认去处：系统「下载」里的 OpenBBS。 */
    private fun saveToDownloads(src: File, name: String, mime: String): Map<String, Any?> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return saveViaMediaStore(src, name, mime)
        }
        @Suppress("DEPRECATION")
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            FOLDER,
        )
        if (!dir.exists() && !dir.mkdirs()) throw IllegalStateException("建不了下载目录")
        val dst = File(dir, uniqueFile(dir, name))
        src.inputStream().use { i -> dst.outputStream().use { o -> i.copyTo(o, 64 * 1024) } }
        return mapOf(
            "uri" to null,
            "display" to "Download/$FOLDER/${dst.name}",
            "path" to dst.absolutePath,
        )
    }

    private fun uniqueFile(dir: File, name: String): String {
        if (!File(dir, name).exists()) return name
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var n = 1
        while (File(dir, "$stem ($n)$ext").exists()) n++
        return "$stem ($n)$ext"
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveViaMediaStore(src: File, name: String, mime: String): Map<String, Any?> {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                Environment.DIRECTORY_DOWNLOADS + "/" + FOLDER,
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val uri = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("系统没有给出下载位置")
        try {
            contentResolver.openOutputStream(uri)?.use { out ->
                src.inputStream().use { it.copyTo(out, 64 * 1024) }
            } ?: throw IllegalStateException("写不进下载目录")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
        // 同名时系统会自动改名，实际名字只有查回来才知道
        var actual = name
        contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) actual = c.getString(0) ?: name }
        return mapOf(
            "uri" to uri.toString(),
            "display" to "Download/$FOLDER/$actual",
            "path" to null,
        )
    }

    // ---------------------------------------------------------------- 打开

    private fun open(uri: String, path: String?, mime: String, result: MethodChannel.Result) {
        try {
            // 只有 content:// 才走这里。file:// 交给 Dart 侧的 open_filex（它带 FileProvider）。
            if (uri.isEmpty()) {
                result.success(false)
                return
            }
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(Uri.parse(uri), mime)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }
}
