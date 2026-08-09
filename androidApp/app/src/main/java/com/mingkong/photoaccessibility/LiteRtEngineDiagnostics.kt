package com.mingkong.photoaccessibility

import android.os.Build

internal data class EngineDiagnostic(
    val ready: Boolean,
    val message: String
)

internal object LiteRtEngineDiagnostics {
    fun inspect(): EngineDiagnostic {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return EngineDiagnostic(false, "需要 Android 8.0 或更高版本")
        }
        if (Build.SUPPORTED_64_BIT_ABIS.none { it == "arm64-v8a" }) {
            val actual = Build.SUPPORTED_ABIS.joinToString().ifBlank { "未知" }
            return EngineDiagnostic(
                false,
                "此安装包需要 arm64-v8a 设备；本机 ABI：$actual"
            )
        }
        return try {
            System.loadLibrary("litertlm_jni")
            EngineDiagnostic(
                true,
                "LiteRT-LM 0.15.0 引擎已包含在 APK 中，并已通过本机原生库加载检查；无需另行下载引擎"
            )
        } catch (error: Throwable) {
            EngineDiagnostic(
                false,
                "LiteRT-LM 内置引擎无法加载：${error.message ?: error.javaClass.simpleName}"
            )
        }
    }
}
