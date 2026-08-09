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

data class RuntimeLoadResult(
    val requestedEngine: InferenceEngine,
    val activeEngineLabel: String,
    val usedFallback: Boolean
)

class LiteRtVisionRuntime(
    resolver: ContentResolver,
    cacheDirectory: File
) : AutoCloseable {
    private val imagePreprocessor = ImagePreprocessor(resolver, cacheDirectory)
    private val modelCache = File(cacheDirectory, "litert-lm-cache").apply { mkdirs() }
    private val lock = Any()
    @Volatile private var engine: Engine? = null
    @Volatile private var loadedKey: String? = null
    @Volatile private var lastLoadResult: RuntimeLoadResult? = null

    suspend fun load(
        modelFile: File,
        model: VisionModel,
        requestedEngine: InferenceEngine
    ): RuntimeLoadResult = withContext(Dispatchers.IO) {
        val key = "${model.name}:${requestedEngine.name}:${modelFile.absolutePath}"
        if (engine != null && loadedKey == key) {
            return@withContext lastLoadResult ?: RuntimeLoadResult(
                requestedEngine, "LiteRT-LM CPU", requestedEngine == InferenceEngine.LITERT_SMART
            )
        }
        detachEngine()?.let { runCatching { it.close() } }

        when (requestedEngine) {
            InferenceEngine.LITERT_CPU -> {
                val created = create(modelFile, useGpu = false)
                RuntimeLoadResult(requestedEngine, "LiteRT-LM CPU", false).also {
                    attach(created, key, it)
                }
            }
            InferenceEngine.LITERT_SMART -> {
                val gpu = runCatching { create(modelFile, useGpu = true) }
                if (gpu.isSuccess) {
                    RuntimeLoadResult(requestedEngine, "LiteRT-LM GPU", false).also {
                        attach(gpu.getOrThrow(), key, it)
                    }
                } else {
                    val cpu = create(modelFile, useGpu = false)
                    RuntimeLoadResult(
                        requestedEngine,
                        "LiteRT-LM CPU（GPU 不兼容，已自动回退）",
                        true
                    ).also { attach(cpu, key, it) }
                }
            }
        }
    }

    suspend fun describe(
        uri: Uri,
        style: DescriptionStyle,
        includeAdvice: Boolean,
        onStage: (String) -> Unit = {}
    ): String = withContext(Dispatchers.IO) {
        val active = engine ?: error("请先下载并加载 LiteRT-LM 本地模型")
        onStage("正在节能预处理照片")
        val prepared = imagePreprocessor.prepare(uri)
        try {
            onStage("正在生成并自检描述；模型输入 ${prepared.width} 乘 ${prepared.height}")
            var generated = parseGenerated(request(
                active,
                prepared.file,
                PromptBuilder.chinese(style, includeAdvice),
                PromptBuilder.tokenBudget(style),
                0.15
            ))
            var candidate = combine(generated, includeAdvice)
            if (!generated.needsReview && generated.uncertainties.isEmpty()) {
                return@withContext candidate
            }

            onStage("检测到疑点，正在独立视觉校对")
            var review = parseReview(request(
                active,
                prepared.file,
                PromptBuilder.review(style, includeAdvice, candidate),
                180,
                0.0
            ))
            if (review.approved) return@withContext candidate

            val issues = review.issues.ifEmpty { listOf("独立校对判定存在实质问题") }
            onStage("校对未通过，正在定向修正")
            generated = parseGenerated(request(
                active,
                prepared.file,
                PromptBuilder.revision(style, includeAdvice, candidate, issues),
                PromptBuilder.tokenBudget(style),
                0.1
            ))
            candidate = combine(generated, includeAdvice)
            onStage("正在复核修正结果")
            review = parseReview(request(
                active,
                prepared.file,
                PromptBuilder.review(style, includeAdvice, candidate),
                180,
                0.0
            ))
            require(review.approved) {
                "修正后的描述仍未通过视觉校对：${review.issues.ifEmpty { issues }.joinToString("；")}"
            }
            candidate
        } finally {
            prepared.file.delete()
        }
    }

    private fun create(modelFile: File, useGpu: Boolean): Engine {
        val mainBackend = if (useGpu) Backend.GPU() else Backend.CPU()
        val visionBackend = if (useGpu) Backend.GPU() else Backend.CPU()
        val created = Engine(EngineConfig(
            modelPath = modelFile.absolutePath,
            backend = mainBackend,
            visionBackend = visionBackend,
            maxNumTokens = 4096,
            maxNumImages = 1,
            cacheDir = modelCache.absolutePath
        ))
        try {
            created.initialize()
            return created
        } catch (error: Throwable) {
            runCatching { created.close() }
            throw error
        }
    }

    private fun request(
        active: Engine,
        image: File,
        prompt: String,
        maximumTokens: Int,
        temperature: Double
    ): String {
        val config = ConversationConfig(
            samplerConfig = SamplerConfig(topK = 20, topP = 0.9, temperature = temperature),
            maxOutputToken = maximumTokens,
            thinkingConfig = ThinkingConfig(enableThinking = false)
        )
        return active.createConversation(config).use { conversation ->
            conversation.sendMessage(
                Contents.of(
                    Content.ImageFile(image.absolutePath),
                    Content.Text(prompt)
                ),
                extraContext = mapOf("enable_thinking" to false),
                thinkingConfig = ThinkingConfig(enableThinking = false)
            ).toString()
        }
    }

    private data class Generated(
        val isPhoto: Boolean,
        val description: String,
        val advice: String,
        val needsReview: Boolean,
        val uncertainties: List<String>
    )

    private data class Review(val approved: Boolean, val issues: List<String>)

    private fun parseGenerated(raw: String): Generated {
        val json = structuredObject(raw)
        return Generated(
            isPhoto = json.optBoolean("isPhoto"),
            description = PromptBuilder.sanitize(json.optString("description")),
            advice = PromptBuilder.sanitize(json.optString("advice")),
            needsReview = json.optBoolean("needsReview", false),
            uncertainties = json.optJSONArray("uncertainties").toStringList()
        ).also { require(it.description.isNotBlank()) { "本地模型没有生成描述" } }
    }

    private fun parseReview(raw: String): Review {
        val json = structuredObject(raw)
        return Review(
            approved = json.optBoolean("approved", false),
            issues = json.optJSONArray("issues").toStringList()
        )
    }

    private fun combine(generated: Generated, includeAdvice: Boolean): String {
        var result = generated.description
        if (includeAdvice && generated.isPhoto) {
            require(generated.advice.isNotBlank()) { "模型遗漏了已启用的拍摄建议" }
            result += " 下次拍摄建议：${generated.advice}"
        }
        return result
    }

    private fun structuredObject(raw: String): JSONObject {
        val cleaned = raw.replace(Regex("<think>[\\s\\S]*?</think>"), "")
            .replace("```json", "").replace("```", "").trim()
        val start = cleaned.indexOf('{')
        val end = cleaned.lastIndexOf('}')
        require(start >= 0 && end > start) { "本地模型没有返回结构化 JSON" }
        return JSONObject(cleaned.substring(start, end + 1))
    }

    private fun org.json.JSONArray?.toStringList(): List<String> = buildList {
        val array = this@toStringList ?: return@buildList
        for (index in 0 until array.length()) {
            array.optString(index).trim().takeIf { it.isNotEmpty() }?.let(::add)
        }
    }

    private fun attach(created: Engine, key: String, result: RuntimeLoadResult) {
        synchronized(lock) {
            engine = created
            loadedKey = key
            lastLoadResult = result
        }
    }

    private fun detachEngine(): Engine? = synchronized(lock) {
        val old = engine
        engine = null
        loadedKey = null
        lastLoadResult = null
        old
    }

    override fun close() {
        detachEngine()?.close()
    }
}
