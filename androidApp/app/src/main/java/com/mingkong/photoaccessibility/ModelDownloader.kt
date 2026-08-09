package com.mingkong.photoaccessibility

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.security.MessageDigest
import javax.net.ssl.SSLException
import kotlin.coroutines.coroutineContext

data class DownloadProgress(
    val downloaded: Long,
    val total: Long,
    val currentStep: String,
    val bytesPerSecond: Long,
    val detail: String? = null,
    val attempt: Int = 1
) {
    val percent: Int
        get() = if (total <= 0) 0 else ((downloaded * 100) / total).toInt().coerceIn(0, 100)
}

internal class NonRetryableDownloadException(message: String) : IOException(message)

private class DownloadActivity(initialBytes: Long) {
    @Volatile var downloaded: Long = initialBytes
    @Volatile var lastChangeMillis: Long = System.currentTimeMillis()

    fun update(value: Long) {
        if (value > downloaded) lastChangeMillis = System.currentTimeMillis()
        downloaded = value
    }
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

internal class ModelDownloader(
    private val context: Context,
    private val httpClient: HuggingFaceHttpClient = HuggingFaceHttpClient()
) {
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
        val modelFile = modelFile(model)
        val partFile = partFile(model)

        if (isReady(model)) {
            onProgress(DownloadProgress(
                model.expectedBytes,
                model.expectedBytes,
                "${model.displayName} 已安装并通过固定版本检查",
                0
            ))
            return@withContext modelFile
        }

        if (modelFile.isFile && modelFile.length() == model.expectedBytes) {
            onProgress(DownloadProgress(
                model.expectedBytes,
                model.expectedBytes,
                "正在校验已有 ${model.displayName}",
                0
            ))
            if (verify(modelFile, model, onProgress)) return@withContext markComplete(model)
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
            require(verify(partFile, model, onProgress)) {
                "${model.displayName} SHA-256 校验失败"
            }
            finishPart(model)
            return@withContext markComplete(model)
        }

        onProgress(DownloadProgress(
            downloaded = partFile.length(),
            total = model.expectedBytes,
            currentStep = "正在检测 ${model.displayName} 下载服务器",
            bytesPerSecond = 0,
            detail = "只请求一个字节，核对权限、重定向和断点支持"
        ))
        val probe = probeRemote(model, huggingFaceToken, partFile.length(), onProgress)
        if (probe.remoteTotalBytes != null && probe.remoteTotalBytes != model.expectedBytes) {
            throw NonRetryableDownloadException(
                "服务器文件大小为 ${DownloadText.bytes(probe.remoteTotalBytes)}，但应用固定版本应为 " +
                    "${DownloadText.bytes(model.expectedBytes)}；已停止下载，请更新应用中的模型清单"
            )
        }
        onProgress(DownloadProgress(
            downloaded = partFile.length(),
            total = model.expectedBytes,
            currentStep = "模型服务器连接正常",
            bytesPerSecond = 0,
            detail = "HTTP ${probe.responseCode}，${probe.redirectCount} 次安全重定向，" +
                (if (probe.supportsRange) "支持断点续传" else "服务器未确认断点支持") +
                (probe.remoteTotalBytes?.let { "；远端大小 ${DownloadText.bytes(it)} 已匹配" } ?: "")
        ))
        ensureStorage(model)

        downloadFile(model, huggingFaceToken, onProgress)
        require(partFile.length() == model.expectedBytes) { "模型下载长度不一致" }
        onProgress(DownloadProgress(
            model.expectedBytes,
            model.expectedBytes,
            "下载完成，正在校验 ${model.displayName} 的 SHA-256",
            0
        ))
        require(verify(partFile, model, onProgress)) {
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

    private suspend fun probeRemote(
        model: VisionModel,
        huggingFaceToken: String?,
        downloaded: Long,
        onProgress: (DownloadProgress) -> Unit
    ): RemoteProbe {
        var lastError: Throwable? = null
        for (attempt in 1..3) {
            try {
                return httpClient.probe(model.downloadUrl, huggingFaceToken)
            } catch (error: NonRetryableDownloadException) {
                throw error
            } catch (error: Throwable) {
                lastError = error
                if (attempt < 3) {
                    onProgress(DownloadProgress(
                        downloaded = downloaded,
                        total = model.expectedBytes,
                        currentStep = "模型服务器探测失败，准备重试",
                        bytesPerSecond = 0,
                        detail = "${friendlyFailure(error)}；${attempt * 2} 秒后第 ${attempt + 1} 次探测",
                        attempt = attempt
                    ))
                    delay(attempt * 2_000L)
                }
            }
        }
        throw IOException("${friendlyFailure(lastError)}；模型服务器探测已尝试 3 次")
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
        val reserve = 256L * 1024 * 1024
        val available = modelDirectory(model).usableSpace.coerceAtLeast(0)
        require(available >= missing + reserve) {
            "存储空间不足：还需下载 ${DownloadText.bytes(missing)}，并保留 256 MB 运行空间；" +
                "当前可用 ${DownloadText.bytes(available)}。可选择更小的模型或释放空间后重试"
        }
    }

    private suspend fun downloadFile(
        model: VisionModel,
        huggingFaceToken: String?,
        onProgress: (DownloadProgress) -> Unit
    ) = coroutineScope {
        val target = partFile(model)
        var lastError: Throwable? = null
        for (attempt in 1..3) {
            coroutineContext.ensureActive()
            val activity = DownloadActivity(target.length().coerceAtMost(model.expectedBytes))
            val heartbeat = launch(Dispatchers.IO) {
                while (isActive) {
                    delay(5_000)
                    val idleSeconds = ((System.currentTimeMillis() - activity.lastChangeMillis) / 1_000)
                        .coerceAtLeast(0)
                    onProgress(DownloadProgress(
                        activity.downloaded,
                        model.expectedBytes,
                        "正在下载 ${model.displayName}",
                        0,
                        if (idleSeconds >= 15) {
                            "连续 ${idleSeconds} 秒未收到新数据；连接会在 30 秒超时后自动重试"
                        } else {
                            "正在连接或等待下一批模型数据"
                        },
                        attempt
                    ))
                }
            }
            try {
                downloadAttempt(model, huggingFaceToken, target, attempt, activity, onProgress)
                heartbeat.cancel()
                return@coroutineScope
            } catch (cancelled: CancellationException) {
                heartbeat.cancel()
                throw cancelled
            } catch (error: NonRetryableDownloadException) {
                heartbeat.cancel()
                throw error
            } catch (error: Throwable) {
                heartbeat.cancel()
                lastError = error
                if (attempt < 3) {
                    onProgress(DownloadProgress(
                        target.length(),
                        model.expectedBytes,
                        "下载连接中断，准备第 ${attempt + 1} 次尝试",
                        0,
                        "${friendlyFailure(error)}；${attempt * 2} 秒后自动断点续传",
                        attempt
                    ))
                    delay(attempt * 2_000L)
                }
            }
        }
        throw IOException("${friendlyFailure(lastError)}；已尝试 3 次，现有进度已保留，请检查后点击重试")
    }

    private suspend fun downloadAttempt(
        model: VisionModel,
        huggingFaceToken: String?,
        target: File,
        attempt: Int,
        activity: DownloadActivity,
        onProgress: (DownloadProgress) -> Unit
    ) {
        var offset = target.length().coerceAtMost(model.expectedBytes)
        val opened = httpClient.openDownload(model.downloadUrl, huggingFaceToken, offset)
        val connection = opened.connection
        try {
            val responseCode = opened.responseCode
            if (offset > 0 && responseCode == HttpURLConnection.HTTP_OK) {
                if (!target.delete()) {
                    throw NonRetryableDownloadException("服务器不支持断点续传，且无法清理旧的临时文件")
                }
                offset = 0
                activity.update(0)
            }
            if (responseCode == HttpURLConnection.HTTP_UNAUTHORIZED ||
                responseCode == HttpURLConnection.HTTP_FORBIDDEN
            ) {
                throw NonRetryableDownloadException(
                    "模型仓库拒绝访问；请确认已接受 Gemma 许可，且 Hugging Face 令牌具有读取权限"
                )
            }
            if (responseCode != HttpURLConnection.HTTP_OK &&
                responseCode != HttpURLConnection.HTTP_PARTIAL
            ) {
                throw IOException("模型服务器返回 HTTP $responseCode")
            }
            if (responseCode == HttpURLConnection.HTTP_PARTIAL) {
                validateContentRange(connection, offset, model.expectedBytes)
            } else if (offset == 0L) {
                val contentLength = connection.contentLengthLong
                if (contentLength >= 0 && contentLength != model.expectedBytes) {
                    throw NonRetryableDownloadException(
                        "服务器文件长度为 ${DownloadText.bytes(contentLength)}，预期为 " +
                            DownloadText.bytes(model.expectedBytes)
                    )
                }
            }

            val speed = DownloadSpeedMeter().also { it.reset(offset) }
            var lastReportedAt = 0L
            onProgress(DownloadProgress(
                offset,
                model.expectedBytes,
                if (offset > 0) "正在断点续传 ${model.displayName}" else "正在下载 ${model.displayName}",
                0,
                "第 $attempt 次连接已建立；经过 ${opened.redirectCount} 次安全重定向到 ${opened.finalHost}",
                attempt
            ))
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
                        if (written > model.expectedBytes) {
                            throw NonRetryableDownloadException(
                                "服务器返回的数据超过固定模型长度，已停止以避免保存损坏文件"
                            )
                        }
                        activity.update(written)
                        val now = System.currentTimeMillis()
                        if (now - lastReportedAt >= 250 || written >= model.expectedBytes) {
                            onProgress(DownloadProgress(
                                written,
                                model.expectedBytes,
                                "正在下载 ${model.displayName}",
                                speed.update(written),
                                null,
                                attempt
                            ))
                            lastReportedAt = now
                        }
                    }
                    output.fd.sync()
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    internal fun friendlyFailure(error: Throwable?): String = when (error) {
        is SocketTimeoutException -> "模型服务器连续 30 秒没有返回数据，连接超时"
        is UnknownHostException -> "无法解析模型服务器地址；请检查网络、DNS 或代理"
        is SSLException -> "与模型服务器建立安全连接失败；请检查系统时间、网络或代理证书"
        is NonRetryableDownloadException -> error.message ?: "模型仓库拒绝下载"
        is IOException -> error.message ?: "网络读写失败"
        null -> "未知下载错误"
        else -> error.message ?: error.javaClass.simpleName
    }

    private fun validateContentRange(
        connection: HttpURLConnection,
        expectedStart: Long,
        expectedTotal: Long
    ) {
        val header = connection.getHeaderField("Content-Range")
            ?: throw IOException("服务器返回断点数据，但缺少 Content-Range")
        val match = CONTENT_RANGE.matchEntire(header.trim())
            ?: throw IOException("服务器返回无法识别的 Content-Range：$header")
        val actualStart = match.groupValues[1].toLongOrNull()
        val actualTotal = match.groupValues[3].toLongOrNull()
        if (actualStart != expectedStart || actualTotal != expectedTotal) {
            throw NonRetryableDownloadException(
                "断点响应不匹配：服务器从 ${actualStart ?: "未知"} 字节开始、总长 " +
                    "${actualTotal?.let(DownloadText::bytes) ?: "未知"}；预期从 $expectedStart 字节开始、" +
                    "总长 ${DownloadText.bytes(expectedTotal)}"
            )
        }
    }

    private suspend fun verify(
        file: File,
        model: VisionModel,
        onProgress: (DownloadProgress) -> Unit
    ): Boolean {
        val digest = MessageDigest.getInstance("SHA-256")
        val speed = DownloadSpeedMeter().also { it.reset(0) }
        var checked = 0L
        var lastReportedAt = 0L
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                coroutineContext.ensureActive()
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
                checked += count
                val now = System.currentTimeMillis()
                if (now - lastReportedAt >= 250 || checked >= file.length()) {
                    onProgress(DownloadProgress(
                        checked,
                        file.length(),
                        "正在校验 ${model.displayName} 的 SHA-256",
                        speed.update(checked),
                        "正在读取本地文件并核对完整性"
                    ))
                    lastReportedAt = now
                }
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
            .equals(model.expectedSha256, ignoreCase = true)
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

    companion object {
        private val CONTENT_RANGE = Regex("bytes\\s+(\\d+)-(\\d+)/(\\d+)", RegexOption.IGNORE_CASE)
    }
}
