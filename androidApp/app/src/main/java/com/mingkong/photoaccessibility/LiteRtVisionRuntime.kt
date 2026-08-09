package com.mingkong.photoaccessibility

import android.content.ContentResolver
import android.net.Uri
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.ai.edge.litertlm.ThinkingConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.util.UUID

class LiteRtVisionRuntime(
    private val resolver: ContentResolver,
    private val cacheDirectory: File
) : AutoCloseable {
    @Volatile private var engine: Engine? = null

    suspend fun load(modelFile: File) = withContext(Dispatchers.IO) {
        if (engine != null) return@withContext
        val modelCache = File(cacheDirectory, "litert-lm-cache").apply { mkdirs() }
        val created = Engine(EngineConfig(
            modelPath = modelFile.absolutePath,
            backend = Backend.CPU(),
            visionBackend = Backend.CPU(),
            maxNumTokens = 4096,
            maxNumImages = 1,
            cacheDir = modelCache.absolutePath
        ))
        try {
            created.initialize()
            synchronized(this@LiteRtVisionRuntime) {
                if (engine == null) engine = created else created.close()
            }
        } catch (error: Throwable) {
            runCatching { created.close() }
            throw error
        }
    }

    suspend fun describe(uri: Uri, style: DescriptionStyle, includeAdvice: Boolean): String =
        withContext(Dispatchers.IO) {
            val active = engine ?: error("请先下载并加载 LiteRT-LM 本地模型")
            val photo = copyToCache(uri)
            try {
                val config = ConversationConfig(
                    samplerConfig = SamplerConfig(topK = 20, topP = 0.9, temperature = 0.2),
                    maxOutputToken = 700,
                    thinkingConfig = ThinkingConfig(enableThinking = false)
                )
                active.createConversation(config).use { conversation ->
                    val response = conversation.sendMessage(
                        Contents.of(
                            Content.ImageFile(photo.absolutePath),
                            Content.Text(PromptBuilder.chinese(style, includeAdvice))
                        ),
                        extraContext = mapOf("enable_thinking" to false),
                        thinkingConfig = ThinkingConfig(enableThinking = false)
                    )
                    parse(response.toString(), includeAdvice)
                }
            } finally {
                photo.delete()
            }
        }

    private fun copyToCache(uri: Uri): File {
        val directory = File(cacheDirectory, "vision-input").apply { mkdirs() }
        val file = File(directory, "${UUID.randomUUID()}.image")
        resolver.openInputStream(uri)?.use { input ->
            file.outputStream().use { output -> input.copyTo(output) }
        } ?: error("无法读取照片")
        return file
    }

    private fun parse(raw: String, includeAdvice: Boolean): String {
        val cleaned = raw.replace(Regex("<think>[\\s\\S]*?</think>"), "")
            .replace("```json", "").replace("```", "").trim()
        val start = cleaned.indexOf('{')
        val end = cleaned.lastIndexOf('}')
        require(start >= 0 && end > start) { "本地模型没有返回结构化描述" }
        val json = JSONObject(cleaned.substring(start, end + 1))
        var result = PromptBuilder.sanitize(json.optString("description"))
        require(result.isNotBlank()) { "本地模型没有生成描述" }
        val advice = PromptBuilder.sanitize(json.optString("advice"))
        if (includeAdvice && json.optBoolean("isPhoto") && advice.isNotBlank()) {
            result += " 下次拍摄建议：$advice"
        }
        return result
    }

    @Synchronized
    override fun close() {
        engine?.close()
        engine = null
    }
}
