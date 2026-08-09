package com.mingkong.photoaccessibility

import java.util.Locale
import java.net.URL

enum class VisionModel(
    val displayName: String,
    val repository: String,
    val revision: String,
    val fileName: String,
    val expectedBytes: Long,
    val expectedSha256: String,
    val requiresHuggingFaceToken: Boolean,
    val recommendation: String
) {
    QWEN_35_4B(
        displayName = "Qwen 3.5 4B",
        repository = "trevon/Qwen3.5-4B-LiteRT",
        revision = "8c81b3a5932f8544fd927c9f095f24baf4ca755a",
        fileName = "model_multimodal.litertlm",
        expectedBytes = 5_263_458_304L,
        expectedSha256 = "09c025bd69d3ef048cd79dc15c8fd5e4602a5b0ddb2555d33a38cd40ed5d5205",
        requiresHuggingFaceToken = false,
        recommendation = "中文照片描述均衡。建议 Android 14 或更高、12GB 内存和近年的旗舰芯片；模型较大，低内存设备优先选择 Gemma 4 E2B。"
    ),
    GEMMA_4_E2B(
        displayName = "Gemma 4 E2B",
        repository = "litert-community/gemma-4-E2B-it-litert-lm",
        revision = "6b78abd019e61a1ca4cbe3b212d2c9ce8ff38a94",
        fileName = "gemma-4-E2B-it.litertlm",
        expectedBytes = 2_588_147_712L,
        expectedSha256 = "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c",
        requiresHuggingFaceToken = false,
        recommendation = "速度、发热和识别质量较均衡，适合移动端。建议 Android 13 或更高、8GB 内存；多数近年中高端或旗舰手机优先安装这一款。"
    ),
    GEMMA_4_E4B(
        displayName = "Gemma 4 E4B",
        repository = "litert-community/gemma-4-E4B-it-litert-lm",
        revision = "2eee7ac325f20eb8c9ac1d0e972f7c84663062da",
        fileName = "gemma-4-E4B-it.litertlm",
        expectedBytes = 3_659_530_240L,
        expectedSha256 = "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0",
        requiresHuggingFaceToken = false,
        recommendation = "比 E2B 更重视细节和复杂画面识别。建议 Android 14 或更高、12GB 内存及旗舰芯片；批量处理时发热和耗电会更高。"
    ),
    GEMMA_3N_E2B(
        displayName = "Gemma 3n E2B",
        repository = "google/gemma-3n-E2B-it-litert-lm",
        revision = "c03b6f60b8da6c5400b6838a2cf26420f80c0a01",
        fileName = "gemma-3n-E2B-it-int4.litertlm",
        expectedBytes = 3_655_827_456L,
        expectedSha256 = "2ed7bc3a0026c93d5b8a4544b352d9d00cd66ff0bac3ef6a20ac3d2cba4010d6",
        requiresHuggingFaceToken = true,
        recommendation = "为手机和平板设计，支持照片输入。建议 Android 13 或更高、8GB 内存；Google 仓库需要先接受 Gemma 许可，并在下载时提供 Hugging Face 读取令牌。"
    ),
    GEMMA_3N_E4B(
        displayName = "Gemma 3n E4B",
        repository = "google/gemma-3n-E4B-it-litert-lm",
        revision = "297ed75955702dec3503e00c2c2ecbbf475300bc",
        fileName = "gemma-3n-E4B-it-int4.litertlm",
        expectedBytes = 4_919_541_760L,
        expectedSha256 = "2e67a6cd51dfe0f793431e6bd4ed8d029c88e10f52ca0469ad38445e3cd3c1f4",
        requiresHuggingFaceToken = true,
        recommendation = "Gemma 3n 中质量更高的一档。建议 Android 14 或更高、12GB 内存和旗舰芯片；需要先接受 Gemma 许可并提供 Hugging Face 读取令牌。"
    );

    val downloadSize: String
        get() = String.format(Locale.US, "约 %.2f GB", expectedBytes / 1_000_000_000.0)

    val downloadUrl: URL
        get() = URL(
            "https://huggingface.co/$repository/resolve/$revision/$fileName?download=true"
        )

    val platformCompatibility: String
        get() = when (this) {
            QWEN_35_4B -> "平台：Android 支持 LiteRT-LM；macOS 支持 MLX 或 Ollama；Windows 当前没有本软件版本。"
            GEMMA_4_E2B -> "平台：Android 支持 LiteRT-LM，适合 8GB 内存设备；macOS 支持 MLX 或 Ollama；Windows 当前没有本软件版本。"
            GEMMA_4_E4B -> "平台：Android 支持 LiteRT-LM，建议 12GB 内存旗舰设备；macOS 支持 MLX 或 Ollama并建议 24GB 内存；Windows 当前没有本软件版本。"
            GEMMA_3N_E2B -> "平台：Android 支持 LiteRT-LM；macOS 使用 MLX 可识别照片，Ollama 包暂不用于照片；Windows 当前没有本软件版本。"
            GEMMA_3N_E4B -> "平台：Android 支持 LiteRT-LM并建议 12GB 内存；macOS 使用 MLX 可识别照片；Windows 当前没有本软件版本。"
        }

    val selectionLabel: String
        get() = "$displayName，$downloadSize。$recommendation $platformCompatibility"

    companion object {
        fun stored(rawValue: String?): VisionModel =
            entries.firstOrNull { it.name == rawValue } ?: QWEN_35_4B
    }
}
