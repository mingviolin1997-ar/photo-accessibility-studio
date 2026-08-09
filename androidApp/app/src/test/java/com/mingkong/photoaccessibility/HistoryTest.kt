package com.mingkong.photoaccessibility

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.TimeUnit

class HistoryTest {
    @Test
    fun historyNameContainsYearMonthDayHourMinuteSecond() {
        val name = defaultHistoryName(1_700_000_000_000)
        assertTrue(name.matches(
            Regex("""^\d{4}年\d{2}月\d{2}日 \d{2}时\d{2}分\d{2}秒$""")
        ))
    }

    @Test
    fun thirtyDayRetentionRemovesExpiredBatch() {
        val now = 2_000_000_000_000
        val recent = HistoryBatch(
            createdAt = now - TimeUnit.DAYS.toMillis(29),
            jobs = emptyList()
        )
        val expired = HistoryBatch(
            createdAt = now - TimeUnit.DAYS.toMillis(31),
            jobs = emptyList()
        )

        val retained = retainHistory(listOf(expired, recent), 30, now)

        assertEquals(listOf(recent.id), retained.map { it.id })
    }
}
