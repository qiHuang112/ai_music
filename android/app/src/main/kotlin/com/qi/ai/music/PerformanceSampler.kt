package com.qi.ai.music

import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal object PerformanceSampler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun sample(result: MethodChannel.Result) {
        worker.execute {
            try {
                // PSS includes Dart/native/graphics memory, unlike Java heap
                // usage. Reading process memory must not block Flutter's UI.
                val memoryBytes = Debug.getPss() * 1024L
                val values = mapOf(
                    "memoryBytes" to memoryBytes,
                    "memoryKind" to "PSS",
                    "cpuTimeMs" to Process.getElapsedCpuTime(),
                    "elapsedTimeMs" to SystemClock.elapsedRealtime(),
                )
                main.post { result.success(values) }
            } catch (error: Exception) {
                main.post { result.error("performance_unavailable", error.message, null) }
            }
        }
    }
}
