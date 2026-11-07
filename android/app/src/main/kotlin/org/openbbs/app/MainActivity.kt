package org.openbbs.app

import android.app.Activity
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
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
        private const val ICON_CHANNEL = "openbbs/icon"
        private const val KEEPALIVE_CHANNEL = "openbbs/keepalive"
        private const val POWER_CHANNEL = "openbbs/power"
        private const val REQ_DIR = 4801
        private const val FOLDER = "OpenBBS"

        /** 图标别名顺序，跟 AndroidManifest.xml 里的 Icon* 一一对应。 */
        private val ICONS = listOf("mint", "blue", "purple", "pink", "coral", "red", "lime", "steel")

        /** 清单里默认启用的那个。 */
        private const val DEFAULT_ICON = "mint"
    }

    // ------------------------------------------------------------ 应用图标

    /**
     * 桌面图标靠 activity-alias 切换。
     *
     * 图标和名字都写在清单里，运行时改不了，所以预置了几套别名，
     * 这里只负责启用其中一个、禁用其余。用 DONT_KILL_APP，切完应用不被杀，
     * 桌面图标要等启动器自己刷新（一般几秒）。
     */
    /**
     * 别名组件的全名。
     *
     * 清单里的 .IconMint 是按 namespace（org.openbbs.app）展开的，不是 applicationId
     * （com.kalutoex.shijianxian）——这两个在这项目里不一样，拿 packageName 拼必然落空。
     * namespace 就是 MainActivity 自己所在的那个包，从类名截出来即可，编译期就定死了。
     *
     * 先问系统要一遍（getPackageInfo 有时不列 alias），要不到再按 namespace 拼。
     */
    @Suppress("DEPRECATION")
    private fun aliasMap(): Map<String, ComponentName> {
        aliasCache?.let { return it }
        val out = HashMap<String, ComponentName>()
        try {
            val info = packageManager.getPackageInfo(packageName, PackageManager.GET_ACTIVITIES)
            for (a in info.activities ?: emptyArray()) {
                val i = a.name.lastIndexOf(".Icon")
                if (i < 0) continue
                val k = a.name.substring(i + 5).lowercase()
                if (k in ICONS) out[k] = ComponentName(a.packageName, a.name)
            }
        } catch (_: Exception) {
            // 拿不到就走下面的 namespace 兜底
        }
        aliasCache = out
        return out
    }

    /** 清单解析用的包名（namespace），不是 applicationId。 */
    private val namespace: String
        get() = MainActivity::class.java.name.substringBeforeLast('.')

    private fun aliasOf(key: String): ComponentName {
        aliasMap()[key]?.let { return it }
        // 注意两个参数不是一回事：第一个是包名（applicationId），
        // 第二个是类全名（namespace 开头）。混了就是 Unknown component。
        val full = "$namespace.Icon${key.replaceFirstChar { it.uppercase() }}"
        return ComponentName(packageName, full)
    }

    private fun currentIcon(): String {
        for (k in ICONS) {
            val c = aliasOf(k)
            val state = packageManager.getComponentEnabledSetting(c)
            val on = when (state) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
                // 没动过就是清单里的初值：只有默认那个是启用的。
                else -> k == DEFAULT_ICON
            }
            if (on) return k
        }
        return DEFAULT_ICON
    }

    private fun setIcon(key: String, result: MethodChannel.Result) {
        if (key !in ICONS) {
            result.error("unknownIcon", "没有这套图标：$key", null)
            return
        }
        val target = aliasOf(key)
        try {
            // 先开新的再关旧的，中间不会出现"一个都没有"的空档。
            packageManager.setComponentEnabledSetting(
                target,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            for (k in ICONS) {
                if (k == key) continue
                packageManager.setComponentEnabledSetting(
                    aliasOf(k),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("iconFailed", e.message ?: e.toString(), null)
        }
    }

    private var aliasCache: Map<String, ComponentName>? = null

    private var dirResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, ICON_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "current" -> result.success(currentIcon())
                    "set" -> setIcon(call.argument<String>("key") ?: "", result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, KEEPALIVE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        UploadService.start(
                            this,
                            call.argument<String>("title") ?: "正在上传",
                            call.argument<String>("text") ?: "",
                        )
                        result.success(true)
                    }
                    "update" -> {
                        // 走 startService 再进一次 onStartCommand，顺手把通知刷新掉
                        UploadService.start(
                            this,
                            call.argument<String>("title") ?: "正在上传",
                            call.argument<String>("text") ?: "",
                        )
                        result.success(true)
                    }
                    "stop" -> {
                        UploadService.stop(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, POWER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoring" -> result.success(isIgnoringBattery())
                    "requestIgnore" -> {
                        requestIgnoreBattery()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
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

    // ---------------------------------------------------------- 电池优化豁免

    /**
     * 是否已经在电池优化白名单里。
     *
     * 白名单里的进程不会被系统当成缓存进程冻住，后台那点定时器才有机会跑。
     * 安卓 6 以下没有这套机制，按已豁免处理。
     */
    private fun isIgnoringBattery(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * 弹系统那个「是否允许忽略电池优化」。
     *
     * 只能由用户点「允许」，第三方 App 没有静默拿到的办法。个别定制系统
     * 不认这个 Intent，退回到白名单列表页让用户自己勾。
     */
    private fun requestIgnoreBattery() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || isIgnoringBattery()) return
        val direct = Intent(
            android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName"),
        )
        try {
            startActivity(direct)
        } catch (_: Exception) {
            try {
                startActivity(Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
                // 两样都不认就算了，别弹崩溃
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
