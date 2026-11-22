package com.ibuki.ibukihome

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var avatarChannel: MethodChannel? = null
    private var novelTextChannel: MethodChannel? = null
    private val avatarExecutor = Executors.newSingleThreadExecutor()
    private val channelName = "com.ibuki.ibukihome/archive"
    private val createArchiveRequest = 47031
    private var pendingSource: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        novelTextChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ibuki.ibukihome/novel-text")
        novelTextChannel!!.setMethodCallHandler { call, result ->
            if (call.method != "decodeLegacyTxt") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            if (bytes == null) {
                result.error("missing_text", "请选择 TXT 文件。", null)
                return@setMethodCallHandler
            }
            avatarExecutor.execute {
                try {
                    val text = NovelTextDecoder.decodeLegacy(bytes)
                    runOnUiThread { result.success(text) }
                } catch (error: Exception) {
                    runOnUiThread { result.error("invalid_text", "无法识别 TXT 编码。", null) }
                } catch (error: OutOfMemoryError) {
                    runOnUiThread { result.error("text_memory", "内存不足，请拆分文件后重试。", null) }
                }
            }
        }
        avatarChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ibuki.ibukihome/profile")
        avatarChannel!!.setMethodCallHandler { call, result ->
            if (call.method != "prepareAvatar" && call.method != "prepareChatImage") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("missing_image", "请选择有效的图片。", null)
                return@setMethodCallHandler
            }
            avatarExecutor.execute {
                try {
                    val png = if (call.method == "prepareChatImage") ChatImageDecoder.prepare(cacheDir, path) else ProfileAvatarDecoder.prepare(cacheDir, path)
                    runOnUiThread { result.success(png) }
                } catch (error: Exception) {
                    runOnUiThread { result.error("avatar_decode_failed", "无法读取这张图片，请选择有效的图片。", null) }
                } catch (error: OutOfMemoryError) {
                    runOnUiThread { result.error("avatar_memory", "这张图片处理失败，请尝试其他图片。", null) }
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method != "saveArchive") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingResult != null) {
                result.error("busy", "A backup save request is already active.", null)
                return@setMethodCallHandler
            }
            val source = call.argument<String>("sourcePath")
            val fileName = call.argument<String>("fileName") ?: "IbukiHome.ibukibackup"
            if (source.isNullOrBlank() || !File(source).isFile) {
                result.error("missing_source", "Backup source file is unavailable.", null)
                return@setMethodCallHandler
            }
            pendingSource = source
            pendingResult = result
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                // A ZIP MIME makes DocumentsUI append ".zip" to the custom
                // .ibukibackup file name. Keep the product extension intact.
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
            startActivityForResult(intent, createArchiveRequest)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != createArchiveRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingResult
        val source = pendingSource
        pendingResult = null
        pendingSource = null
        if (resultCode != Activity.RESULT_OK || data?.data == null || source == null) {
            result?.success(false)
            return
        }
        try {
            copyToUri(File(source), data.data!!)
            result?.success(true)
        } catch (error: Exception) {
            result?.error("save_failed", error.javaClass.simpleName, null)
        }
    }

    override fun onDestroy() {
        avatarChannel?.setMethodCallHandler(null)
        novelTextChannel?.setMethodCallHandler(null)
        avatarExecutor.shutdown()
        super.onDestroy()
    }

    private fun copyToUri(source: File, destination: Uri) {
        contentResolver.openOutputStream(destination, "w").use { output ->
            requireNotNull(output) { "Unable to open selected destination." }
            source.inputStream().buffered().use { input -> input.copyTo(output, 64 * 1024) }
        }
    }
}
