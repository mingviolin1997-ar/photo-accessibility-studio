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
    private val modelsDirectory = File(context.filesDir, "models")

    fun modelDirectory(model: VisionModel) = File(modelsDirectory, model.name.lowercase())
    fun modelFile(model: VisionModel) = File(modelDirectory(model), model.fileName)
    private fun partFile(model: VisionModel) = File(modelDirectory(model), "${model.fileName}.part")
    private fun completedFile(model: VisionModel) = File(modelDirectory(model), ".download-complete")

    fun isReady(model: VisionModel): Boolean =
        modelFile(model).isFile &&
            modelFile(model).length() == model.expectedBytes &&
            completedFile(model).readTextOrEmpty().lineSequence().any {
                it.equals(model.expectedSha256, ignoreCase = true)
            }

    fun installedModels(): Set<VisionModel> = VisionModel.entries.filterTo(mutableSetOf(), ::isReady)

    suspend fun download(
        model: VisionModel,
        huggingFaceToken: String? = null,
        onProgress: (DownloadProgress) -> Unit
    ): File = withContext(Dispatchers.IO) {
        if (model.requiresHuggingFaceToken) {
            require(!huggingFaceToken.isNullOrBlank()) {
                "此模型需要 Hugging Face 读取令牌；请先在模型页面接受 Gemma 许可"
            }
        }
        modelDirectory(model).mkdirs()
        ensureStorage(model)
        val modelFile = modelFile(model)
        val partFile = partFile(model)

        if (modelFile.isFile && modelFile.length() == model.expectedBytes) {
            onProgress(DownloadProgress(
                model.expectedBytes,
                model.expectedBytes,
                "正在校验已有 ${model.displayName}",
                0
            ))
            if (verify(modelFile, model.expectedSha256)) return@withContext markComplete(model)
            require(modelFile.delete()) { "已有模型校验失败且无法删除" }
        }

        if (partFile.length() > model.expectedBytes) {
            require(partFile.delete()) { "无法清理无效下载文件" }
        }
        if (partFile.length() == model.expectedBytes) {
            onProgress(DownloadProgress(
                model.expectedBytes,
                model.expectedBytes,
                "正在校验已下载的 ${model.displayName}",
                0
            ))
            require(verify(partFile, model.expectedSha256)) {
                "${model.displayName} SHA-256 校验失败"
            }
            finishPart(model)
            return@withContext markComplete(model)
        }

        downloadFile(model, huggingFaceToken, onProgress)
        require(partFile.length() == model.expectedBytes) { "模型下载长度不一致" }
        onProgress(DownloadProgress(
            model.expectedBytes,
            model.expectedBytes,
            "下载完成，正在校验 ${model.displayName} 的 SHA-256",
            0
        ))
        require(verify(partFile, model.expectedSha256)) {
            "${model.displayName} SHA-256 校验失败"
        }
        finishPart(model)
        markComplete(model).also {
            onProgress(DownloadProgress(
                model.expectedBytes,
                model.expectedBytes,
                "${model.displayName} 下载、安装与校验完成",
                0
            ))
        }
    }

    fun delete(model: VisionModel): Boolean {
        val directory = modelDirectory(model)
        if (!directory.exists()) return true
        return directory.deleteRecursively()
    }

    private fun ensureStorage(model: VisionModel) {
        val missing = when {
            modelFile(model).length() == model.expectedBytes -> 0
            else -> (model.expectedBytes - partFile(model).length()).coerceAtLeast(0)
        }
        val storage = context.getSystemService(StorageManager::class.java)
        val allocatable = storage.getAllocatableBytes(storage.getUuidForPath(modelDirectory(model)))
        require(allocatable > missing + 768L * 1024 * 1024) {
            "存储空间不足；${model.displayName} ${model.downloadSize}，另需至少 768MB 校验和缓存空间"
        }
    }

    private suspend fun downloadFile(
        model: VisionModel,
        huggingFaceToken: String?,
        onProgress: (DownloadProgress) -> Unit
    ) {
        val target = partFile(model)
        var offset = target.length().coerceAtMost(model.expectedBytes)
        val url = "https://huggingface.co/${model.repository}/resolve/${model.revision}/${model.fileName}?download=true"
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 30_000
        connection.readTimeout = 120_000
        connection.setRequestProperty("Accept-Encoding", "identity")
        if (!huggingFaceToken.isNullOrBlank()) {
            connection.setRequestProperty("Authorization", "Bearer ${huggingFaceToken.trim()}")
        }
        if (offset > 0) connection.setRequestProperty("Range", "bytes=$offset-")
        connection.connect()

        if (offset > 0 && connection.responseCode == HttpURLConnection.HTTP_OK) {
            require(target.delete()) { "服务器不支持断点续传，且无法重新开始下载" }
            offset = 0
        }
        if (connection.responseCode == HttpURLConnection.HTTP_UNAUTHORIZED ||
            connection.responseCode == HttpURLConnection.HTTP_FORBIDDEN
        ) {
            connection.disconnect()
            error("模型仓库拒绝访问；请确认已接受 Gemma 许可，且 Hugging Face 令牌具有读取权限")
        }
        require(connection.responseCode == HttpURLConnection.HTTP_OK ||
            connection.responseCode == HttpURLConnection.HTTP_PARTIAL) {
            "模型下载失败：HTTP ${connection.responseCode}"
        }

        val speed = DownloadSpeedMeter().also { it.reset(offset) }
        var lastReportedSpeed = -1L
        onProgress(DownloadProgress(
            offset,
            model.expectedBytes,
            "正在下载 ${model.displayName}",
            0
        ))
        try {
            FileOutputStream(target, offset > 0).use { output ->
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
                        if (currentSpeed != lastReportedSpeed || written >= model.expectedBytes) {
                            onProgress(DownloadProgress(
                                written,
                                model.expectedBytes,
                                "正在下载 ${model.displayName}",
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

    private fun verify(file: File, expectedSha256: String): Boolean {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
            .equals(expectedSha256, ignoreCase = true)
    }

    private fun finishPart(model: VisionModel) {
        val modelFile = modelFile(model)
        val partFile = partFile(model)
        if (modelFile.exists()) require(modelFile.delete()) { "无法替换旧模型" }
        require(partFile.renameTo(modelFile)) { "无法完成模型的原子安装" }
    }

    private fun markComplete(model: VisionModel): File {
        completedFile(model).writeText(
            "${model.repository}\n${model.revision}\n${model.expectedBytes}\n${model.expectedSha256}\n"
        )
        return modelFile(model)
    }

    private fun File.readTextOrEmpty(): String = runCatching { readText() }.getOrDefault("")
}
