package com.mingkong.photoaccessibility

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PromptAndDownloadTest {
    @Test fun everyDescriptionModeProducesStructuredAccessibilityPrompt() {
        DescriptionStyle.entries.forEach { style ->
            val prompt = PromptBuilder.chinese(style, includeAdvice = true)
            assertTrue(prompt.contains(style.instruction))
            assertTrue(prompt.contains("盲人"))
            assertTrue(prompt.contains("isPhoto"))
        }
    }

    @Test fun speedMeterUsesElapsedTimeAndSmoothsUpdates() {
        var now = 0L
        val meter = DownloadSpeedMeter { now }
        meter.reset(0)
        now = 1_000_000_000L
        assertEquals(1_000_000L, meter.update(1_000_000L))
        now = 2_000_000_000L
        assertEquals(1_300_000L, meter.update(3_000_000L))
    }
}
