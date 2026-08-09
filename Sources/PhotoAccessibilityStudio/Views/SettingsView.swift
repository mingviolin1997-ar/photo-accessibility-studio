import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("interfaceTextScale") private var textScale = 1.0
    @AppStorage("descriptionStyle") private var descriptionStyle = DescriptionStyle.medium.rawValue
    @AppStorage("includeCaptureAdvice") private var includeCaptureAdvice = false
    @AppStorage("autoWriteAfterRecognition") private var autoWriteAfterRecognition = true

    var body: some View {
        Form {
            Section("本地模型") {
                LabeledContent("模型", value: "qwen3.5:4b")
                LabeledContent("服务地址", value: "127.0.0.1:11434")
                Text("照片只发送到本机 Ollama，不会上传到网络。")
                    .foregroundStyle(.secondary)
            }
            Section("描述方式") {
                Picker("描述详细度", selection: $descriptionStyle) {
                    ForEach(DescriptionStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityHint("设置之后新生成的描述详细程度；已生成的草稿不会自动改变")

                Toggle("加入下次拍摄建议", isOn: $includeCaptureAdvice)
                    .accessibilityHint("在照片描述末尾加入基于画面证据的简短拍摄改进建议")
                Text("摄影家模式会使用构图、视角、景深、曝光、光质和色彩关系等专业词语。拍摄建议只针对画面中确实可见的问题或提升空间。")
                    .foregroundStyle(.secondary)
            }
            Section("批量处理") {
                Toggle("识别完成后自动写入已选照片", isOn: $autoWriteAfterRecognition)
                    .accessibilityHint("默认开启；每张照片默认选中，也可单独取消或使用全部取消")
                Text("开启后无需逐张审核或再次确认。写入仍会验证扁平 XMP 字段、文件名、尺寸和像素，失败时恢复原图。")
                    .foregroundStyle(.secondary)
            }
            Section("无障碍") {
                Slider(value: $textScale, in: 1...2, step: 0.25) {
                    Text("界面文本大小")
                } minimumValueLabel: {
                    Text("100%")
                } maximumValueLabel: {
                    Text("200%")
                }
                .accessibilityValue("百分之 \(Int(textScale * 100))")
                Text("文本缩放接口已保留，后续视觉美化不得删除控件语义、键盘路径或焦点环。")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .accessibilityElement(children: .contain)
    }
}
