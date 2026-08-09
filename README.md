# 照片无障碍描述

面向盲人和低视力用户的本地批量照片描述工具。Mac 与 Android 版本都会调用本机 Qwen3.5 4B，为照片生成准确、简洁的中文视觉描述，并将结果写入直接扁平的 XMP-iptcExt:ArtworkContentDescription 字段。

## 轻量安装与首次配置

安装包不内置数 GB 的模型。

- 首次启动只检查本机，不会偷偷下载。
- 缺少环境或模型时，先弹窗说明下载大小并询问是否自动配置。
- 同意后显示当前步骤、进度、已下载/总大小和实时速度；拒绝后保持离线，可稍后从模型状态或设置重新尝试。
- Mac 会按需配置 Ollama、ExifTool 和 qwen3.5:4b，并复用已安装的可用环境。
- Android 内置 LiteRT-LM 0.15.0 推理运行库，按需断点下载固定版本的 Qwen3.5 4B 多模态模型，完成后核对文件长度和 SHA-256。

## 批量工作流

1. 添加一张、多张照片或整个文件夹。
2. 选择低、中、高或摄影家描述模式，并决定是否加入下次拍摄建议。
3. 每张照片默认勾选；开始识别后默认自动写入，无需逐张确认。
4. 也可全部取消、单独勾选、编辑描述后再批量或单张写入。
5. 写入后自动验证字段逐字一致、XMP 是直接扁平结构、没有错误的 AOContentDescription，并确认文件名、尺寸和解码像素签名没有变化。验证失败时不报告成功，并尝试恢复原图。

软件不会使用 Apple 预览进行写入或验证。

## Mac 版

- macOS 14 或更高版本，Apple Silicon。
- 本地推理使用 Ollama qwen3.5:4b。
- ExifTool 仅用于注入应用刻意构造的原始 XMP packet，以及写后回读；不会使用可能生成嵌套字段的普通高层赋值。

构建与测试：

    swift test
    zsh scripts/build-app.sh

生成位置：outputs/照片无障碍描述-macOS.zip。

## Android 版

Android 代码位于 android 分支和 androidApp/ 目录。

- Android 8.0（API 26）或更高版本，当前测试包面向 64 位 ARM 手机。
- LiteRT-LM 0.15.0 运行库随 APK 提供，APK 不包含模型。
- 首次模型下载约 5.26GB，建议预留至少 6GB 空间。
- 模型固定到 trevon/Qwen3.5-4B-LiteRT 提交 8c81b3a…，并校验 SHA-256 09c025bd…。
- 当前 Android 测试版只对 JPEG、PNG 执行可验证的原地扁平 XMP 写入；其他格式会明确失败，不会静默改名或转换。

构建与测试：

    cd androidApp
    ./gradlew testDebugUnitTest assembleDebug

## 隐私、模型与许可

照片只进入设备本地推理引擎。只有用户确认自动配置时，软件才连接 Ollama、GitHub、SourceForge 或 Hugging Face 下载所需公开组件。

项目源代码使用 [MIT License](LICENSE)。第三方运行库、工具和模型保留各自许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
