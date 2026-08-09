package com.mingkong.photoaccessibility

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

internal data class RemoteProbe(
    val responseCode: Int,
    val finalHost: String,
    val supportsRange: Boolean,
    val redirectCount: Int,
    val remoteTotalBytes: Long?
)

internal data class OpenedDownload(
    val connection: HttpURLConnection,
    val responseCode: Int,
    val finalHost: String,
    val redirectCount: Int
)

/**
 * Hugging Face large files redirect to a signed CDN URL. Handle each redirect
 * explicitly so Range survives and the private token never leaves
 * huggingface.co. This behavior is deterministic across Android releases.
 */
internal class HuggingFaceHttpClient(
    private val connectionFactory: (URL) -> HttpURLConnection = {
        it.openConnection() as HttpURLConnection
    }
) {
    fun probe(source: URL, token: String?): RemoteProbe {
        val opened = open(source, token, "bytes=0-0")
        try {
            rejectAccessErrors(opened.responseCode)
            if (opened.responseCode != HttpURLConnection.HTTP_OK &&
                opened.responseCode != HttpURLConnection.HTTP_PARTIAL
            ) {
                throw IOException("模型服务器探测失败：HTTP ${opened.responseCode}")
            }
            opened.connection.inputStream.use { input ->
                if (input.read() < 0) throw IOException("模型服务器没有返回探测数据")
            }
            return RemoteProbe(
                responseCode = opened.responseCode,
                finalHost = opened.finalHost,
                supportsRange = opened.responseCode == HttpURLConnection.HTTP_PARTIAL,
                redirectCount = opened.redirectCount,
                remoteTotalBytes = remoteTotalBytes(opened.connection, opened.responseCode)
            )
        } finally {
            opened.connection.disconnect()
        }
    }

    fun openDownload(source: URL, token: String?, offset: Long): OpenedDownload =
        open(source, token, if (offset > 0) "bytes=$offset-" else null)

    private fun open(source: URL, token: String?, range: String?): OpenedDownload {
        var current = source
        repeat(MAX_REDIRECTS + 1) { redirectCount ->
            val connection = connectionFactory(current)
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 20_000
            connection.readTimeout = 30_000
            connection.setRequestProperty("Accept-Encoding", "identity")
            connection.setRequestProperty("User-Agent", "PhotoAccessibilityStudio-Android/0.8")
            if (!token.isNullOrBlank() && isHuggingFaceHost(current.host)) {
                connection.setRequestProperty("Authorization", "Bearer ${token.trim()}")
            }
            if (range != null) connection.setRequestProperty("Range", range)
            connection.connect()
            val responseCode = connection.responseCode
            if (responseCode !in REDIRECT_CODES) {
                return OpenedDownload(connection, responseCode, current.host, redirectCount)
            }
            val location = connection.getHeaderField("Location")
            connection.disconnect()
            if (location.isNullOrBlank()) {
                throw IOException("模型服务器返回重定向，但没有提供目标地址")
            }
            current = URL(current, location)
        }
        throw IOException("模型下载重定向超过 $MAX_REDIRECTS 次，已停止以避免循环")
    }

    private fun rejectAccessErrors(responseCode: Int) {
        if (responseCode == HttpURLConnection.HTTP_UNAUTHORIZED ||
            responseCode == HttpURLConnection.HTTP_FORBIDDEN
        ) {
            throw NonRetryableDownloadException(
                "模型仓库拒绝访问；如果是 Gemma 3n，请先接受许可并输入有效的 Hugging Face 读取令牌"
            )
        }
    }

    private fun remoteTotalBytes(connection: HttpURLConnection, responseCode: Int): Long? {
        if (responseCode == HttpURLConnection.HTTP_PARTIAL) {
            val contentRange = connection.getHeaderField("Content-Range") ?: return null
            return contentRange.substringAfterLast('/', "")
                .takeUnless { it == "*" }
                ?.toLongOrNull()
        }
        return connection.contentLengthLong.takeIf { it >= 0 }
    }

    private fun isHuggingFaceHost(host: String): Boolean =
        host.equals("huggingface.co", ignoreCase = true) ||
            host.endsWith(".huggingface.co", ignoreCase = true)

    companion object {
        private const val MAX_REDIRECTS = 8
        private val REDIRECT_CODES = setOf(301, 302, 303, 307, 308)
    }
}
