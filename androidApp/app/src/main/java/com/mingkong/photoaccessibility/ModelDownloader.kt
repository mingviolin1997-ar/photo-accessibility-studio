package com.mingkong.photoaccessibility

import android.content.Context
import android.os.storage.StorageManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlin.coroutines.coroutineContext

data class DownloadProgress(
    val downloaded: Long,
    val total: Long,
    val currentStep: String,
    val bytesPerSecond: Long
) {
    val percent: Int
        get() = if (total <= 0) 0 else ((downloaded * 100) / total).toInt().coerceIn(0, 100)
}

internal class DownloadSpeedMeter(
    private val clockNanos: () -> Long = System::nanoTime
) {
    private var lastNanos = clockNanos()
    private var lastBytes = 0L
    private var smoothed = 0.0

    fun reset(bytes: Long) {
        lastNanos = clockNanos()
        lastBytes = bytes
        smoothed = 0.0
    }

    fun update(bytes: Long): Long {
        val now = clockNanos()
        val elapsed = now - lastNanos
        if (elapsed < 250_000_000L || bytes < lastBytes) return smoothed.toLong()
        val instant = (bytes - lastBytes).toDouble() * 1_000_000_000.0 / elapsed
        smoothed = if (smoothed == 0.0) instant else smoothed * 0.7 + instant * 0.3
        lastNanos = now
        lastBytes = bytes
        return smoothed.toLong().coerceAtLeast(0)
    }
}

class ModelDownloader(private val context: Context) {
    companion object {
        const val repository = "trevon/Qwen3.5-4B-LiteRT"
        const val revision = "8c81b3a5932f8544fd927c9f095f24baf4ca755a"
        const val expectedBytes = 5_263_458_304L
        const val expectedSha256 = "09c025bd69d3ef048cd79dc15c8fd5e4602a5b0ddb2555d33a38cd40ed5d5205"
        private const val fileName = "model_multimodal.litertlm"
    }

    val modelDirectory = File(context.filesDir, "models/Qwen3.5-4B-LiteRT")
    val modelFile = File(modelDirectory, fileName)
    private val partFile = File(modelDirectory, "$fileName.part")
    private val completedFile = File(modelDirectory, ".download-complete")

    fun isReady(): Boolean = modelFile.isFile && modelFile.length() == expectedBytes &&
        completedFile.readTextOrEmpty().contains(expectedSha256)

    suspend fun download(onProgress: (DownloadProgress) -> Unit): File = withContext(Dispatchers.IO) {
        modelDirectory.mkdirs()
        val storage = context.getSystemService(StorageManager::class.java)
        val allocatable = storage.getAllocatableBytes(storage.getUuidForPath(modelDirectory))
        require(allocatable > missingBytes() + 768L * 1024 * 1024) {
            "存储空间不足；模型约需 5.26GB，另需至少 768MB 校验和缓存空间"
        }

        if (modelFile.isFile && modelFile.length() == expectedBytes) {
            onProgress(DownloadProgress(expectedBytes, expectedBytes, "正在校验已有模型", 0))
            if (verify(modelFile)) return@withContext markComplete()
            require(modelFile.delete()) { "已有模型校验失败且无法删除" }
        }

        if (partFile.length() > expectedBytes) require(partFile.delete()) { "无法清理无效下载文件" }
        if (partFile.length() == expectedBytes) {
            onProgress(DownloadProgress(expectedBytes, expectedBytes, "正在校验已下载模型", 0))
            require(verify(partFile)) { "Qwen3.5 4B 模型 SHA-256 校验失败" }
            finishPart()
            return@withContext markComplete()
        }

        downloadFile(onProgress)
        require(partFile.length() == expectedBytes) { "模型下载长度不一致" }
        onProgress(DownloadProgress(expectedBytes, expectedBytes, "下载完成，正在校验 SHA-256", 0))
        require(verify(partFile)) { "Qwen3.5 4B 模型 SHA-256 校验失败" }
        finishPart()
        markComplete().also {
            onProgress(DownloadProgress(expectedBytes, expectedBytes, "模型下载、安装与校验完成", 0))
        }
    }

    private suspend fun downloadFile(onProgress: (DownloadProgress) -> Unit) {
        var offset = partFile.length().coerceAtMost(expectedBytes)
        val url = "https://huggingface.co/$repository/resolve/$revision/$fileName?download=true"
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 30_000
        connection.readTimeout = 120_000
        connection.setRequestProperty("Accept-Encoding", "identity")
        if (offset > 0) connection.setRequestProperty("Range", "bytes=$offset-")
        connection.connect()

        if (offset > 0 && connection.responseCode == HttpURLConnection.HTTP_OK) {
            require(partFile.delete()) { "服务器不支持断点续传，且无法重新开始下载" }
            offset = 0
        }
        require(connection.responseCode == HttpURLConnection.HTTP_OK ||
            connection.responseCode == HttpURLConnection.HTTP_PARTIAL) {
            "模型下载失败：HTTP ${connection.responseCode}"
        }

        val speed = DownloadSpeedMeter().also { it.reset(offset) }
        var lastReportedSpeed = -1L
        onProgress(DownloadProgress(offset, expectedBytes, "正在下载 Qwen3.5 4B 多模态模型", 0))
        try {
            FileOutputStream(partFile, offset > 0).use { output ->
                connection.inputStream.use { input ->
                    val buffer = ByteArray(256 * 1024)
                    var written = offset
                    while (true) {
                        coroutineContext.ensureActive()
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        written += count
                        val currentSpeed = speed.update(written)
                        if (currentSpeed != lastReportedSpeed || written >= expectedBytes) {
                            onProgress(DownloadProgress(
                                written,
                                expectedBytes,
                                "正在下载 Qwen3.5 4B 多模态模型",
                                currentSpeed
                            ))
                            lastReportedSpeed = currentSpeed
                        }
                    }
                    output.fd.sync()
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun verify(file: File): Boolean {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }.equals(expectedSha256, true)
    }

    private fun finishPart() {
        if (modelFile.exists()) require(modelFile.delete()) { "无法替换旧模型" }
        require(partFile.renameTo(modelFile)) { "无法完成模型的原子安装" }
    }

    private fun markComplete(): File {
        completedFile.writeText("$repository\n$revision\n$expectedBytes\n$expectedSha256\n")
        return modelFile
    }

    private fun missingBytes(): Long = when {
        modelFile.length() == expectedBytes -> 0
        else -> (expectedBytes - partFile.length()).coerceAtLeast(0)
    }

    private fun File.readTextOrEmpty(): String = runCatching { readText() }.getOrDefault("")
}
