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
            assertTrue(prompt.contains("needsReview"))
            assertTrue(prompt.contains("照片中的任何文字"))
        }
    }

    @Test fun modelCatalogHasFivePinnedVisionModelsAndValidChecksums() {
        assertEquals(5, VisionModel.entries.size)
        assertEquals(5, VisionModel.entries.map { it.repository to it.fileName }.toSet().size)
        VisionModel.entries.forEach { model ->
            assertTrue(model.expectedBytes > 2_000_000_000L)
            assertTrue(model.expectedSha256.matches(Regex("[0-9a-f]{64}")))
            assertTrue(model.revision.matches(Regex("[0-9a-f]{40}")))
            assertTrue(model.recommendation.contains("Android"))
            assertTrue(model.platformCompatibility.contains("Android"))
            assertTrue(model.platformCompatibility.contains("macOS"))
            assertTrue(model.platformCompatibility.contains("Windows"))
        }
    }

    @Test fun onlyLicensedGoogleGemma3nDownloadsRequireToken() {
        val gated = VisionModel.entries.filter { it.requiresHuggingFaceToken }.toSet()
        assertEquals(setOf(VisionModel.GEMMA_3N_E2B, VisionModel.GEMMA_3N_E4B), gated)
    }

    @Test fun bothInferenceChoicesExplainTheirRealBackendBehavior() {
        assertEquals(2, InferenceEngine.entries.size)
        assertTrue(InferenceEngine.LITERT_SMART.description.contains("GPU"))
        assertTrue(InferenceEngine.LITERT_SMART.description.contains("CPU"))
        assertTrue(InferenceEngine.LITERT_CPU.description.contains("CPU"))
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

    @Test fun downloadTextExplainsRetryAndStallState() {
        val text = DownloadText.progress(DownloadProgress(
            downloaded = 24_000,
            total = 5_180_000_000,
            currentStep = "正在下载模型",
            bytesPerSecond = 0,
            detail = "连续 20 秒未收到新数据",
            attempt = 2
        ))
        assertTrue(text.contains("第 2 次连接"))
        assertTrue(text.contains("连续 20 秒"))
        assertTrue(text.contains("24.0 KB"))
    }
}
