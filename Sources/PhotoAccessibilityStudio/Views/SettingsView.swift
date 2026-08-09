import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: BatchViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("interfaceTextScale") private var textScale = 1.0
    @AppStorage("descriptionStyle") private var descriptionStyle = DescriptionStyle.medium.rawValue
    @AppStorage("includeCaptureAdvice") private var includeCaptureAdvice = false
    @AppStorage("alwaysRunIndependentReview") private var alwaysRunIndependentReview = false
    @AppStorage("autoWriteAfterRecognition") private var autoWriteAfterRecognition = false
    @AppStorage("progressSoundEnabled") private var progressSoundEnabled = true
    @AppStorage("historyRetentionDays") private var historyRetentionDays = 30

    var body: some View {
        Form {
            Section("推理引擎") {
                LabeledContent("当前引擎", value: viewModel.selectedInferenceEngine.displayName)
                ForEach(InferenceEngine.allCases) { engine in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(engine.displayName)
                                .font(.headline)
                            if engine == .mlx {
                                Text("推荐")
                                    .font(.caption.weight(.semibold))
                                    .accessibilityLabel("推荐引擎")
                            }
                        }
                        Text(engine.statusDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button(engine == viewModel.selectedInferenceEngine
                               ? "当前使用"
                               : "切换到 \(engine.displayName)") {
                            dismiss()
                            viewModel.chooseInferenceEngine(engine)
                        }
                        .disabled(engine == viewModel.selectedInferenceEngine
                                  || viewModel.isRuntimeInstalling
                                  || viewModel.isProcessing)
                        .accessibilityHint("切换后先检测本机；缺少环境或模型时会询问是否自动下载")
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                }
            }
            Section("本地模型") {
                LabeledContent("当前照片识别模型", value: viewModel.selectedVisionModel.displayName)
                LabeledContent("服务地址", value: viewModel.selectedInferenceEngine.serviceAddress)
                Text("应用保持轻量；缺少环境时会先征求同意，再自动下载、安装和校验。照片只发送到这台 Mac 上的 \(viewModel.selectedInferenceEngine.displayName)，不会上传给云端模型。")
                    .foregroundStyle(.secondary)
                Button("重新检查或自动配置 \(viewModel.selectedInferenceEngine.displayName)") {
                    dismiss()
                    viewModel.checkModel()
                }
                .disabled(viewModel.isRuntimeInstalling)
                .accessibilityHint("检查推理引擎、ExifTool 和当前模型；缺少时先弹窗征求下载同意")

                ForEach(VisionModel.allCases) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(model.displayName)
                                .font(.headline)
                            Spacer()
                            Text(model.downloadSize(for: viewModel.selectedInferenceEngine))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(model.recommendation(for: viewModel.selectedInferenceEngine))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button(modelButtonTitle(model)) {
                            viewModel.installOrSelect(model)
                        }
                        .disabled(modelButtonDisabled(model))
                        .accessibilityHint(model.supportsPhotoRecognition(on: viewModel.selectedInferenceEngine)
                            ? "先检测本机；已安装则直接启用，未安装才下载并配置"
                            : "先检测本机；未安装才下载。当前 macOS Ollama 包不能接收照片，因此不会替换正在使用的视觉模型")
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .contain)
                }

                if let progress = viewModel.runtimeProgress,
                   viewModel.isRuntimeInstalling {
                    Text(progress.step)
                        .font(.callout.weight(.semibold))
                    if let fraction = progress.fraction {
                        ProgressView(value: fraction)
                            .accessibilityLabel("模型下载和配置进度")
                            .accessibilityValue("百分之 \(Int(fraction * 100))")
                    } else {
                        ProgressView()
                            .accessibilityLabel("正在检查或配置模型")
                    }
                    Text(progress.detail)
                        .font(.caption.monospacedDigit())
                }
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
                Toggle("每张都进行第二次独立视觉校对", isOn: $alwaysRunIndependentReview)
                    .accessibilityHint("关闭时使用单次生成内自检，只在发现疑点时启动独立校对；开启后更严格，但大约增加一倍推理时间和耗电")
                Text("默认采用节能的自适应校对：模型先在一次推理中完成描述和自检，只有发现视觉疑点才运行独立校对与定向修正。")
                    .foregroundStyle(.secondary)
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
        .onAppear { viewModel.refreshInstalledModels() }
    }

    private func isInstalled(_ model: VisionModel) -> Bool {
        let identifier = model.identifier(for: viewModel.selectedInferenceEngine)
        return viewModel.installedModelNames.contains(where: {
            $0 == identifier || $0.hasPrefix(identifier + ":")
        })
    }

    private func modelButtonTitle(_ model: VisionModel) -> String {
        if viewModel.installingModelID == model { return "正在检查和配置…" }
        if model.supportsPhotoRecognition(on: viewModel.selectedInferenceEngine),
           viewModel.selectedVisionModel == model,
           isInstalled(model) { return "当前使用" }
        if isInstalled(model) {
            return model.supportsPhotoRecognition(on: viewModel.selectedInferenceEngine)
                ? "设为当前模型" : "已下载（暂不用于照片）"
        }
        return model.supportsPhotoRecognition(on: viewModel.selectedInferenceEngine)
            ? "下载、配置并使用" : "下载并配置"
    }

    private func modelButtonDisabled(_ model: VisionModel) -> Bool {
        if viewModel.isRuntimeInstalling { return true }
        if !model.supportsPhotoRecognition(on: viewModel.selectedInferenceEngine)
            && isInstalled(model) { return true }
        return model.supportsPhotoRecognition(on: viewModel.selectedInferenceEngine)
            && viewModel.selectedVisionModel == model
            && isInstalled(model)
    }
}
