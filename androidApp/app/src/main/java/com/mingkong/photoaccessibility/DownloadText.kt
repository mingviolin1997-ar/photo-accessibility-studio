package com.mingkong.photoaccessibility

import java.util.Locale

object DownloadText {
    fun bytes(value: Long): String = when {
        value >= 1_000_000_000 -> String.format(Locale.US, "%.2f GB", value / 1_000_000_000.0)
        value >= 1_000_000 -> String.format(Locale.US, "%.1f MB", value / 1_000_000.0)
        value >= 1_000 -> String.format(Locale.US, "%.1f KB", value / 1_000.0)
        else -> "$value B"
    }

    fun progress(value: DownloadProgress): String {
        val amount = "${bytes(value.downloaded)} / ${bytes(value.total)}"
        val speed = if (value.bytesPerSecond > 0) "，${bytes(value.bytesPerSecond)}/秒" else ""
        val attempt = if (value.attempt > 1) "，第 ${value.attempt} 次连接" else ""
        val detail = value.detail?.takeIf { it.isNotBlank() }?.let { "。$it" } ?: ""
        return "${value.currentStep}：$amount$speed$attempt$detail"
    }
}
