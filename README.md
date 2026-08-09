# 照片无障碍描述（macOS 测试版）

原生 macOS 批处理工具，调用本机 Ollama 的 `qwen3.5:4b` 为照片生成中文无障碍视觉描述。应用自动构造原始 XMP packet，将描述写入 Apple Preview/iPhone 使用的直接扁平 `XMP-iptcExt:ArtworkContentDescription` 字段，并执行结构、字段、文件名、尺寸与像素完整性检查。

## 当前工作流

1. `Command-O` 批量添加照片。
2. 点击“开始识别”，照片只会发送到 `127.0.0.1` 的 Ollama。
3. 每张照片默认选中；识别完成后自动写入。可单独取消，也可使用“全选写入”或“全部取消”。
4. 如需精修，可关闭自动写入，在检查器内编辑后手动批量写入。
5. 应用逐字读回字段，验证 XMP 为直接扁平结构且没有错误的 `AOContentDescription`，并确认文件名、像素尺寸和解码像素摘要没有改变。

已有 Image Description 会单独显示。默认选中的照片会按批处理设置自动写入；取消选择即可跳过。写入前创建临时安全副本；失败时自动恢复。

## 依赖

- macOS 14 或更高版本，Apple Silicon
- Ollama 与 `qwen3.5:4b`
- ExifTool（Homebrew：`brew install exiftool`）

## 开发与测试

```bash
swift test
zsh scripts/build-app.sh
```

生成的测试版位于 `outputs/照片无障碍描述.app`。

## Android 版本

Android 测试版在 `android` 分支开发，安装包会发布到 GitHub Releases。Android 端通过局域网调用运行 `qwen3.5:4b` 的 Ollama 服务，并在设备上完成原始扁平 XMP 写入与完整性验证。

## 隐私与许可

Mac 版只连接本机 Ollama。项目不收集分析数据，不上传照片到第三方服务。源代码使用 [MIT License](LICENSE)。
