package com.qi.ai.music

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File

class AudioShareProvider : FileProvider()

internal object AudioFileSharing {
    fun open(activity: Activity, path: String, name: String?, chooserTitle: String?) {
        val file = File(path).canonicalFile
        val root = File(activity.filesDir, "ai_music_cache").canonicalFile
        require(file.isFile && file.path.startsWith(root.path + File.separator)) {
            "Audio file is unavailable"
        }
        val extension = file.extension.lowercase()
        require(extension in setOf("mp3", "flac", "m4a", "wav", "ogg", "ape", "aac", "opus", "wma", "aiff", "alac")) {
            "Only audio files can be shared"
        }
        val displayName = (name ?: file.nameWithoutExtension)
            .replace(Regex("""[\p{Cntrl}/\\]"""), "_")
            .trim().take(140).ifBlank { "audio" } + "." + extension
        val uri = FileProvider.getUriForFile(activity, activity.packageName + ".share", file, displayName)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "audio/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TITLE, displayName)
            clipData = ClipData.newRawUri(displayName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(Intent.createChooser(send, chooserTitle ?: "Share audio").apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }
}
