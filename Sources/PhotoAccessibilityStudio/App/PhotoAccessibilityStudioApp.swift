import SwiftUI

@main
struct PhotoAccessibilityStudioApp: App {
    @StateObject private var viewModel = BatchViewModel()
    @AppStorage("interfaceTextScale") private var textScale = 1.0

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "autoWriteAfterRecognition": false,
            "descriptionStyle": DescriptionStyle.medium.rawValue,
            "includeCaptureAdvice": false,
            "alwaysRunIndependentReview": false,
            "selectedVisionModel": VisionModel.qwen35_4B.ollamaName,
            "selectedVisionModelID": VisionModel.qwen35_4B.rawValue,
            "progressSoundEnabled": true,
            "historyRetentionDays": 30
        ])
        if !defaults.bool(forKey: "exportWorkflowV2Migration") {
            defaults.set(false, forKey: "autoWriteAfterRecognition")
            defaults.set(true, forKey: "exportWorkflowV2Migration")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 960, minHeight: 620)
                .dynamicTypeSize(dynamicTypeSize)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("设置…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("添加照片…") { viewModel.choosePhotos() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("添加文件夹…") { viewModel.chooseFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("开始识别") { viewModel.startRecognition() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!viewModel.canRecognize)
                Button("写入已选照片") { viewModel.writeSelectedDescriptions() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!viewModel.canWrite)
                Button("批量导出已选结果…") { viewModel.chooseExportFolder() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!viewModel.canExport)
                Button("删除当前所选素材") { viewModel.removeSelected() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(!viewModel.canDeleteSelected)
            }
            CommandMenu("显示") {
                Button("放大文本") { textScale = min(2, textScale + 0.25) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("缩小文本") { textScale = max(1, textScale - 0.25) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("实际大小") { textScale = 1 }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }

    private var dynamicTypeSize: DynamicTypeSize {
        switch textScale {
        case ..<1.125: return .medium
        case ..<1.375: return .large
        case ..<1.625: return .xLarge
        case ..<1.875: return .xxLarge
        default: return .accessibility1
        }
    }
}
