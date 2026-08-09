package com.mingkong.photoaccessibility

object PromptBuilder {
    fun chinese(style: DescriptionStyle, includeAdvice: Boolean): String {
        val advice = if (includeAdvice) {
            "如果这是现实拍摄的照片，再给一条适合盲人下次拍摄时执行的建议，优先检查主体是否完整、镜头遮挡、抖动、焦点、曝光、背景干扰、水平和距离。没有明确问题可以说保持现有拍法。非照片的截图、插画、文档或界面必须返回空 advice。"
        } else {
            "advice 必须返回空字符串。"
        }
        return """
            你是为盲人快速理解图像服务的中文无障碍描述员。先判断输入是现实照片、截图、文档、插画、海报还是其他图形。
            准确优先：不要猜测人物身份、关系、意图、情绪、地点或敏感属性；不确定时明确使用“似乎”或省略。可见文字应准确抄录。平面图形不要虚构景深、焦点或曝光。
            描述顺序：图像类型与整体场景；主体及重要空间位置；人物或动物、动作和关键物体；可见文字；颜色、光线和整体叙事。主观感受最多一句，并以“画面给人……”开头。
            详细度要求：${style.instruction}
            $advice
            只返回一个 JSON 对象，不要 Markdown：{"isPhoto":true或false,"description":"中文描述","advice":"中文建议或空字符串"}
        """.trimIndent()
    }

    fun sanitize(value: String): String = value
        .replace("```json", "").replace("```", "")
        .replace(Regex("^(无障碍描述|图片描述|图像描述)[:：]\\s*"), "")
        .trim().split(Regex("\\s+")).joinToString(" ")
}
