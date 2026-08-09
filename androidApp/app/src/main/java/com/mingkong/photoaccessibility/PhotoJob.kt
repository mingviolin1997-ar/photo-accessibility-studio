package com.mingkong.photoaccessibility

import android.net.Uri
import java.util.UUID

enum class JobStatus(val label: String) {
    WAITING("等待识别"),
    RECOGNIZING("正在识别"),
    READY("描述已生成"),
    WRITING("正在写入并验证"),
    COMPLETED("已写入并自动验证"),
    FAILED("处理失败")
}

data class PhotoJob(
    val id: String = UUID.randomUUID().toString(),
    val uri: Uri,
    val displayName: String,
    val mimeType: String?,
    var selectedForWriting: Boolean = true,
    var status: JobStatus = JobStatus.WAITING,
    var description: String = "",
    var error: String? = null
)
