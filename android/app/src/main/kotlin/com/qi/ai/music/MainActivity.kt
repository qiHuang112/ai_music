package com.qi.ai.music

import com.ryanheise.audioservice.AudioServiceActivity
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
