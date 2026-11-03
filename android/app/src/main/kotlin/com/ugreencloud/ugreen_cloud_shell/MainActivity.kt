package com.ugreencloud.ugreen_cloud_shell

import android.app.KeyguardManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.hardware.fingerprint.FingerprintManager
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.webkit.MimeTypeMap
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/// MIUI 自带文件管理器的包名与「选文件」入口 Activity。
private const val MIUI_FILE_MANAGER_PACKAGE = "com.android.fileexplorer"
private const val MIUI_FILE_MANAGER_PICKER =
    "com.android.fileexplorer.picker.PickMainNavigatorActivity"

/// 指纹走 FingerprintManager；宿主保持 FragmentActivity（历史原因 + 方便以后
/// 换回 androidx.biometric 的 BiometricPrompt）。
class MainActivity : FlutterFragmentActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var fingerprintSink: EventChannel.EventSink? = null
    private var fingerprintCancel: CancellationSignal? = null

    /// 网页 <input type="file"> 触发时，这里挂着一个等待中的 Flutter 调用结果。
    private var filePickerResult: MethodChannel.Result? = null

    /// 系统文件选择器（SAF）。用 ACTION_OPEN_DOCUMENT 而不是 GET_CONTENT：
    /// 前者返回的 content:// 可以持久授权，WebView 渲染进程之后才能一直读到文件。
    private val filePickerLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { activityResult ->
            val result = filePickerResult
            filePickerResult = null
            if (result == null) {
                return@registerForActivityResult
            }
            if (activityResult.resultCode != RESULT_OK) {
                // 用户取消：给网页一个空列表，等同于「没选文件」。
                result.success(emptyList<String>())
                return@registerForActivityResult
            }
            val data = activityResult.data
            val uris = mutableListOf<Uri>()
            val clip = data?.clipData
            if (clip != null) {
                for (index in 0 until clip.itemCount) {
                    clip.getItemAt(index)?.uri?.let { uris.add(it) }
                }
            }
            if (uris.isEmpty()) {
                data?.data?.let { uris.add(it) }
            }
            for (uri in uris) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (_: Exception) {
                    // 有些提供方（如部分网盘）不支持持久授权，本次会话仍可读。
                }
            }
            result.success(uris.map { it.toString() })
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ugreen_shell/file_picker",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFiles" -> {
                    if (filePickerResult != null) {
                        result.error("BUSY", "已有一个文件选择正在进行", null)
                        return@setMethodCallHandler
                    }
                    val multiple = call.argument<Boolean>("multiple") ?: false
                    val mimeTypes = call.argument<List<String>>("mimeTypes") ?: emptyList()
                    filePickerResult = result
                    val launched = launchPicker(multiple, mimeTypes)
                    if (!launched) {
                        filePickerResult = null
                        result.error("NO_PICKER", "无法打开系统文件选择器", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ugreen_shell/immersive",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setImmersive" -> {
                    applyImmersiveMode(call.arguments as? Boolean ?: true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ugreen_shell/fingerprint_events",
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    fingerprintSink = events
                }

                override fun onCancel(arguments: Any?) {
                    fingerprintSink = null
                    cancelFingerprint()
                }
            },
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ugreen_shell/fingerprint",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(fingerprintStatus())
                "start" -> {
                    startFingerprint()
                    result.success(null)
                }
                "cancel" -> {
                    cancelFingerprint()
                    result.success(null)
                }
                "openEnroll" -> result.success(openFingerprintEnroll())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ugreen_shell/files",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val source = call.argument<String>("source") ?: ""
                    val fileName = call.argument<String>("fileName") ?: ""
                    val mimeType = call.argument<String>("mimeType") ?: ""
                    Thread {
                        val target = try {
                            saveToDownloads(source, fileName, mimeType)
                        } catch (e: Exception) {
                            null
                        }
                        mainHandler.post {
                            if (target != null) {
                                result.success(target)
                            } else {
                                result.error("SAVE_FAILED", "无法写入下载目录", null)
                            }
                        }
                    }.start()
                }
                "openFile" -> {
                    val target = call.argument<String>("target") ?: ""
                    Thread {
                        val opened = try {
                            openFile(target)
                        } catch (e: Exception) {
                            false
                        }
                        mainHandler.post { result.success(opened) }
                    }.start()
                }
                "deleteFile" -> {
                    val target = call.argument<String>("target") ?: ""
                    Thread {
                        val deleted = try {
                            removeDownloadFile(target)
                        } catch (e: Exception) {
                            false
                        }
                        mainHandler.post { result.success(deleted) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    /// 选文件：MIUI 上用系统自带文件管理器（分类/最近/多选都熟），其他 ROM 走
    /// Android 默认的 ACTION_OPEN_DOCUMENT（DocumentUI）。逐级回退，保证一定有得选。
    private fun launchPicker(multiple: Boolean, mimeTypes: List<String>): Boolean {
        for (intent in pickerCandidates(multiple, mimeTypes)) {
            try {
                filePickerLauncher.launch(intent)
                return true
            } catch (_: Exception) {
                // 这个选择器不存在或拒绝，试下一个。
            }
        }
        return false
    }

    private fun pickerCandidates(multiple: Boolean, mimeTypes: List<String>): List<Intent> {
        val mime = if (mimeTypes.size == 1) mimeTypes[0] else "*/*"
        val out = mutableListOf<Intent>()
        if (isMiui()) {
            // MIUI 文件管理器的选择入口；显式指定可以避免被 DocumentUI 抢走。
            out.add(
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    component = ComponentName(MIUI_FILE_MANAGER_PACKAGE, MIUI_FILE_MANAGER_PICKER)
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mime
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )
            // 万一个别 MIUI 版本改了组件名，仍然让系统自己挑 GET_CONTENT 的实现。
            out.add(
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mime
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )
        }
        out.add(
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mime
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
                if (mimeTypes.isNotEmpty() && mime != "*/*") {
                    putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
                }
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                )
            },
        )
        return out
    }

    /// 是否 MIUI：小米机型或系统里带 MIUI 版本属性。
    private fun isMiui(): Boolean {
        if (Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true)) {
            return true
        }
        return try {
            val clazz = Class.forName("android.os.SystemProperties")
            val getter = clazz.getMethod("get", String::class.java)
            val version = getter.invoke(null, "ro.miui.ui.version.name") as? String
            if (version.isNullOrEmpty()) false else true
        } catch (_: Exception) {
            false
        }
    }

    /// 读取指纹硬件状态：有没有传感器、系统里有没有录入。
    /// 走的是旧的 FingerprintManager（只能指纹，但界面完全由我们自己画，
    /// BiometricPrompt 的弹窗是系统画的、改不了样式）。
    private fun fingerprintStatus(): Map<String, Any> {
        val manager = getSystemService(Context.FINGERPRINT_SERVICE) as? FingerprintManager
        val hardware = manager?.isHardwareDetected() == true
        val enrolled = manager?.hasEnrolledFingerprints() == true
        return mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "hardware" to hardware,
            "enrolled" to enrolled,
            "deviceSecure" to ((getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)?.isDeviceSecure ?: false),
        )
    }

    /// 开始监听指纹，结果通过 EventChannel 推给 Flutter 自己画的弹窗。
    private fun startFingerprint() {
        val manager = getSystemService(Context.FINGERPRINT_SERVICE) as? FingerprintManager
        if (manager == null || !manager.isHardwareDetected()) {
            emitFingerprint("error", 1, "当前设备没有指纹传感器")
            return
        }
        if (!manager.hasEnrolledFingerprints()) {
            emitFingerprint("error", 2, "系统里还没有录入指纹")
            return
        }
        if (fingerprintCancel != null) {
            return
        }
        val cancel = CancellationSignal()
        fingerprintCancel = cancel
        try {
            @Suppress("DEPRECATION")
            manager.authenticate(
                null,
                cancel,
                0,
                object : FingerprintManager.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: FingerprintManager.AuthenticationResult?) {
                        fingerprintCancel = null
                        emitFingerprint("success")
                    }

                    override fun onAuthenticationFailed() {
                        // 手指不匹配：不算结束，等下一次按压。
                        emitFingerprint("failed")
                    }

                    override fun onAuthenticationHelp(helpMsgId: Int, helpString: CharSequence?) {
                        emitFingerprint("help", helpMsgId, helpString?.toString().orEmpty())
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                        fingerprintCancel = null
                        emitFingerprint("error", errorCode, errString?.toString().orEmpty())
                    }
                },
                null,
            )
        } catch (e: Exception) {
            fingerprintCancel = null
            emitFingerprint("error", -1, e.message ?: "指纹识别启动失败")
        }
    }

    private fun cancelFingerprint() {
        val cancel = fingerprintCancel ?: return
        fingerprintCancel = null
        try {
            cancel.cancel()
        } catch (_: Exception) {
            // 已经结束了。
        }
    }

    private fun emitFingerprint(state: String, code: Int = 0, message: String = "") {
        val payload = mapOf("state" to state, "code" to code, "message" to message)
        mainHandler.post { fingerprintSink?.success(payload) }
    }

    /// 跳到系统的指纹录入页面。
    private fun openFingerprintEnroll(): Boolean {
        val intents = mutableListOf<Intent>()
        try {
            intents.add(Intent("android.settings.FINGERPRINT_ENROLL"))
        } catch (_: Exception) {
            // 个别 ROM 没有这个 action。
        }
        intents.add(Intent(Settings.ACTION_SECURITY_SETTINGS))
        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // 试下一个入口。
            }
        }
        return false
    }

    /// 隐藏状态栏与底部导航栏（含手势小白条），只保留下滑临时唤出。
    private fun applyImmersiveMode(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            val controller = window.insetsController ?: return
            if (enabled) {
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                controller.hide(WindowInsets.Type.systemBars())
            } else {
                controller.show(WindowInsets.Type.systemBars())
            }
            return
        }
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = if (enabled) {
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN
        } else {
            View.SYSTEM_UI_FLAG_VISIBLE
        }
    }

    /// 把临时文件写入系统“下载”目录的 Ugreen_Pro_For_Pad 子目录，
    /// 返回 content:// URI（API 29+）或文件路径。
    private fun saveToDownloads(source: String, fileName: String, mimeType: String): String {
        val src = File(source)
        if (!src.exists()) {
            throw IOException("源文件不存在")
        }
        src.inputStream().use { input ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/Ugreen_Pro_For_Pad"
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType.ifBlank { guessMime(fileName) })
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                }
                val uri = contentResolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: throw IOException("MediaStore insert failed")
                try {
                    contentResolver.openOutputStream(uri)?.use { out ->
                        input.copyTo(out)
                    } ?: throw IOException("无法打开输出流")
                } catch (e: Exception) {
                    contentResolver.delete(uri, null, null)
                    throw e
                }
                return uri.toString()
            }
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "Ugreen_Pro_For_Pad",
            )
            if (!dir.exists()) {
                dir.mkdirs()
            }
            var file = File(dir, fileName)
            var index = 1
            while (file.exists()) {
                val dot = fileName.lastIndexOf('.')
                val base = if (dot > 0) fileName.substring(0, dot) else fileName
                val ext = if (dot > 0) fileName.substring(dot) else ""
                file = File(dir, "$base($index)$ext")
                index++
            }
            FileOutputStream(file).use { out ->
                input.copyTo(out)
            }
            return file.absolutePath
        }
    }

    private fun guessMime(fileName: String): String {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: "application/octet-stream"
    }

    /// 用系统应用打开文件，返回是否成功。
    private fun openFile(target: String): Boolean {
        val uri = if (target.startsWith("content:") || target.startsWith("file:")) {
            Uri.parse(target)
        } else {
            Uri.fromFile(File(target))
        }
        val mime = contentResolver.getType(uri) ?: guessMime(target)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_ACTIVITY_NEW_TASK
            )
        }
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /// 删除已下载的文件，返回是否成功。
    private fun removeDownloadFile(target: String): Boolean {
        return if (target.startsWith("content:")) {
            contentResolver.delete(Uri.parse(target), null, null) > 0
        } else {
            val path = if (target.startsWith("file:")) {
                Uri.parse(target).path ?: target
            } else {
                target
            }
            File(path).delete()
        }
    }
}
