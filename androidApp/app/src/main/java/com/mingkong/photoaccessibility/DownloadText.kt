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
        return "${value.currentStep}：$amount$speed"
    }
}
