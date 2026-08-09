package com.mingkong.photoaccessibility

enum class InferenceEngine(
    val displayName: String,
    val description: String
) {
    LITERT_SMART(
        "LiteRT-LM 智能加速（推荐）",
        "优先使用手机 GPU；设备或驱动不兼容时自动回退 CPU。适合较新的 8GB 或更大内存 Android 手机。"
    ),
    LITERT_CPU(
        "LiteRT-LM CPU 兼容模式",
        "始终使用 CPU，兼容性最好、耗电和速度较保守。适合 GPU 初始化失败或需要稳定批处理的设备。"
    );

    companion object {
        fun stored(rawValue: String?): InferenceEngine? =
            entries.firstOrNull { it.name == rawValue }
    }
}
