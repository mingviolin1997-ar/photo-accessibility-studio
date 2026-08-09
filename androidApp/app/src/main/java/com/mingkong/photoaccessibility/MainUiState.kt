package com.mingkong.photoaccessibility

data class MainUiState(
    val jobs: List<PhotoJob> = emptyList(),
    val history: List<HistoryBatch> = emptyList(),
    val status: String = "请选择照片开始。",
    val modelStatus: String = "正在检查本地模型。",
    val progress: Int = 0,
    val modelProgress: Int = 0,
    val modelProgressText: String = "",
    val downloadingModel: Boolean = false,
    val engineChoicePending: Boolean = false,
    val modelChoicePending: Boolean = false,
    val setupPromptPending: Boolean = false,
    val busy: Boolean = false,
    val modelReady: Boolean = false,
    val selectedEngine: InferenceEngine = InferenceEngine.LITERT_SMART,
    val selectedModel: VisionModel = VisionModel.QWEN_35_4B,
    val installedModels: Set<VisionModel> = emptySet(),
    val activeEngineLabel: String = "尚未加载",
    val style: DescriptionStyle = DescriptionStyle.MEDIUM,
    val includeAdvice: Boolean = false,
    val autoWrite: Boolean = true,
    val historyRetentionDays: Int = 30
)
