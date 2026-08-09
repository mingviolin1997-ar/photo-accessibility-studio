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
}
