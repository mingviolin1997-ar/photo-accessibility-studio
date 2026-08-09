package com.mingkong.photoaccessibility

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.net.HttpURLConnection
import java.net.URL

class HuggingFaceHttpClientTest {
    private var server: MockWebServer? = null

    @After fun stopServer() {
        server?.shutdown()
    }

    @Test fun redirectKeepsRangeButDoesNotLeakTokenToCdn() {
        val local = MockWebServer().also { server = it }
        local.enqueue(MockResponse()
            .setResponseCode(302)
            .addHeader("Location", "https://cdn.example/file"))
        local.enqueue(MockResponse()
            .setResponseCode(206)
            .addHeader("Content-Range", "bytes 0-0/100")
            .setBody("x"))
        local.start()
        val client = HuggingFaceHttpClient { requested ->
            local.url(requested.path).toUrl().openConnection() as HttpURLConnection
        }

        val probe = client.probe(URL("https://huggingface.co/start"), "hf_secret")

        val first = local.takeRequest()
        val second = local.takeRequest()
        assertEquals(206, probe.responseCode)
        assertTrue(probe.supportsRange)
        assertEquals(1, probe.redirectCount)
        assertEquals(100L, probe.remoteTotalBytes)
        assertEquals("bytes=0-0", first.getHeader("Range"))
        assertEquals("Bearer hf_secret", first.getHeader("Authorization"))
        assertEquals("bytes=0-0", second.getHeader("Range"))
        assertNull(second.getHeader("Authorization"))
    }

    @Test fun publicModelEndpointsReturnOneByteThroughRealCdnRedirects() {
        assumeTrue(System.getenv("PAS_RUN_ANDROID_NETWORK_TEST") == "1")
        val client = HuggingFaceHttpClient()
        listOf(
            VisionModel.QWEN_35_4B,
            VisionModel.GEMMA_4_E2B,
            VisionModel.GEMMA_4_E4B
        ).forEach { model ->
            val probe = client.probe(model.downloadUrl, null)
            assertEquals(model.displayName, 206, probe.responseCode)
            assertTrue(model.displayName, probe.supportsRange)
            assertTrue(model.displayName, probe.redirectCount >= 1)
            assertEquals(model.displayName, model.expectedBytes, probe.remoteTotalBytes)
        }
    }

    @Test fun gatedRepositoryExplainsLicenseInsteadOfRetryingBlindly() {
        val local = MockWebServer().also { server = it }
        local.enqueue(MockResponse().setResponseCode(401).setBody("unauthorized"))
        local.start()
        val client = HuggingFaceHttpClient { requested ->
            local.url(requested.path).toUrl().openConnection() as HttpURLConnection
        }

        val error = runCatching {
            client.probe(URL("https://huggingface.co/google/gated"), "invalid")
        }.exceptionOrNull()

        assertTrue(error is NonRetryableDownloadException)
        assertTrue(error?.message.orEmpty().contains("Gemma 3n"))
        assertTrue(error?.message.orEmpty().contains("令牌"))
    }
}
