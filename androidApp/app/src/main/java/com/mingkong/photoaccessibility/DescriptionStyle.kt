package com.mingkong.photoaccessibility

enum class DescriptionStyle(val label: String, val instruction: String) {
    LOW("低：快速了解", "用一到两句、约40到70字，只说图像类型、主体、关键位置和重要文字。"),
    MEDIUM("中：均衡描述", "用约80到140字，说明主体、空间关系、动作、重要物体、文字、颜色和光线。"),
    HIGH("高：详细描述", "用约150到260字，按整体到局部描述，并补充有助于理解情境的可靠细节。"),
    PHOTOGRAPHER(
        "摄影家模式",
        "用约170到300字，在准确描述内容后，以专业摄影角度说明构图、视角、景深、曝光、光质、色彩关系和视觉重心。"
    )
}
