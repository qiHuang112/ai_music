package com.qi.ai.music

import com.ryanheise.audioservice.AudioServiceActivity
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.net.Uri
import androidx.core.content.FileProvider

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai_music/app_update")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "info" -> {
                            val info = packageManager.getPackageInfo(packageName, 0)
                            result.success(mapOf(
                                "versionName" to info.versionName,
                                "versionCode" to if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong(),
                                "builtAt" to BuildConfig.BUILD_TIMESTAMP,
                                "channel" to BuildConfig.BUILD_TYPE,
                                "abis" to Build.SUPPORTED_ABIS.toList()
                            ))
                        }
                        "install" -> {
                            if (BuildConfig.BUILD_TYPE != "release") throw IllegalArgumentException("Debug 版本不能安装 release 更新")
                            val apk = File(call.argument<String>("path") ?: "").canonicalFile
                            val updateDir = File(cacheDir, "ai_music_updates").canonicalFile
                            if (apk.parentFile != updateDir || !apk.isFile || apk.extension != "apk") throw IllegalArgumentException("更新包路径无效")
                            val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                            val archive = packageManager.getPackageArchiveInfo(apk.path, flags) ?: throw IllegalArgumentException("更新包无效")
                            val installed = packageManager.getPackageInfo(packageName, flags)
                            fun version(info: android.content.pm.PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                            val requested = call.argument<Number>("versionCode")?.toLong()
                            if (archive.packageName != packageName || version(archive) != requested || version(archive) <= version(installed)) throw IllegalArgumentException("更新包版本或应用不符")
                            if (archive.applicationInfo?.flags?.and(ApplicationInfo.FLAG_DEBUGGABLE) != 0) throw IllegalArgumentException("更新包不是 release 版本")
                            fun signatures(info: android.content.pm.PackageInfo): Set<String> {
                                val signs = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
                                return signs?.map { it.toCharsString() }?.toSet() ?: emptySet()
                            }
                            val archiveSignatures = signatures(archive)
                            if (archiveSignatures.isEmpty() || archiveSignatures != signatures(installed)) throw IllegalArgumentException("签名不一致，无法保留数据覆盖安装")
                            if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                                result.success(false)
                            } else {
                                val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
                                startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                result.success(true)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) { result.error("update_failed", error.message, null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai_music/screenshot_ocr")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path.isNullOrBlank() || !File(path).isFile) {
                    result.error("invalid_image", "Image file is unavailable", null)
                    return@setMethodCallHandler
                }
                val recognizer = TextRecognition.getClient(
                    ChineseTextRecognizerOptions.Builder().build()
                )
                try {
                    recognizer.process(InputImage.fromFilePath(this, android.net.Uri.fromFile(File(path))))
                        .addOnSuccessListener { recognized ->
                            val lines = recognized.textBlocks.flatMap { block ->
                                block.lines.mapNotNull { line ->
                                    val box = line.boundingBox ?: return@mapNotNull null
                                    mapOf(
                                        "text" to line.text,
                                        "left" to box.left.toDouble(),
                                        "top" to box.top.toDouble(),
                                        "right" to box.right.toDouble(),
                                        "bottom" to box.bottom.toDouble()
                                    )
                                }
                            }
                            result.success(lines)
                            recognizer.close()
                        }
                        .addOnFailureListener { error ->
                            result.error("ocr_failed", error.message, null)
                            recognizer.close()
                        }
                } catch (error: Exception) {
                    result.error("ocr_failed", error.message, null)
                    recognizer.close()
                }
            }
    }
}
