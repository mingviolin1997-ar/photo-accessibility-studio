import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: BatchViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("interfaceTextScale") private var textScale = 1.0
    @AppStorage("descriptionStyle") private var descriptionStyle = DescriptionStyle.medium.rawValue
    @AppStorage("includeCaptureAdvice") private var includeCaptureAdvice = false
    @AppStorage("autoWriteAfterRecognition") private var autoWriteAfterRecognition = false
    @AppStorage("progressSoundEnabled") private var progressSoundEnabled = true
    @AppStorage("historyRetentionDays") private var historyRetentionDays = 30

    var body: some View {
        Form {
            Section("本地模型") {
                LabeledContent("模型", value: "qwen3.5:4b")
                LabeledContent("服务地址", value: "127.0.0.1:11434")
                Text("应用保持轻量；缺少环境时会先征求同意，再自动下载、安装和校验。照片只发送到本机 Ollama，不会上传到网络。")
                    .foregroundStyle(.secondary)
                Button("重新检查或自动配置本地环境") {
                    dismiss()
                    viewModel.checkModel()
                }
                .disabled(viewModel.isRuntimeInstalling)
                .accessibilityHint("检查 Ollama、ExifTool 和 Qwen 模型；缺少时先弹窗征求下载同意")
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
                Toggle("识别完成后直接写入原始照片", isOn: $autoWriteAfterRecognition)
                    .accessibilityHint("默认关闭；建议确认右侧校对结果后，使用批量导出生成带描述的副本")
                Text("推荐保持关闭并使用“批量导出”，避免在确认前修改原始素材。直接写入或导出都会验证扁平 XMP 字段、文件名、尺寸和像素。")
                    .foregroundStyle(.secondary)
            }
            Section("历史记录") {
                Stepper("历史默认保留 \(historyRetentionDays) 天",
                        value: $historyRetentionDays,
                        in: 1...365)
                    .onChange(of: historyRetentionDays) { _, newValue in
                        viewModel.applyHistoryRetention(days: newValue)
                    }
                    .accessibilityHint("超过保留天数的软件历史记录会自动清理，不删除磁盘里的原始照片或导出文件")
                Button("立即清空全部历史记录", role: .destructive) {
                    viewModel.clearHistory()
                }
                .disabled(viewModel.historyBatches.isEmpty)
                Text("历史只保存软件中的照片引用和描述。清除历史、自动过期或从当前工作区删除，都不会删除磁盘中的原始照片和导出文件。")
                    .foregroundStyle(.secondary)
            }
            Section("无障碍") {
                Toggle("播放识别进度声音", isOn: $progressSoundEnabled)
                    .accessibilityHint("识别期间每秒播放轻声提示；音调随进度升高，百分之五十和完成时使用不同声音")
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
