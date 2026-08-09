package com.mingkong.photoaccessibility

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit

data class HistoryBatch(
    val id: String = UUID.randomUUID().toString(),
    val createdAt: Long = System.currentTimeMillis(),
    val name: String = defaultHistoryName(createdAt),
    val jobs: List<PhotoJob>
)

fun defaultHistoryName(timestamp: Long): String =
    SimpleDateFormat("yyyy年MM月dd日 HH时mm分ss秒", Locale.SIMPLIFIED_CHINESE)
        .format(Date(timestamp))

fun retainHistory(
    batches: List<HistoryBatch>,
    days: Int,
    now: Long = System.currentTimeMillis()
): List<HistoryBatch> {
    val safeDays = days.coerceIn(1, 365)
    val cutoff = now - TimeUnit.DAYS.toMillis(safeDays.toLong())
    return batches
        .filter { it.createdAt >= cutoff }
        .sortedByDescending { it.createdAt }
}
