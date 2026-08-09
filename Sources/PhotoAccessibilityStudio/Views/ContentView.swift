import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: BatchViewModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                queueHeader
                List(viewModel.jobs, selection: $viewModel.selectionID) { job in
                    PhotoRowView(job: job,
                                 isSelectedForWriting: viewModel.bindingForApproval(id: job.id))
                        .tag(job.id)
                }
                .accessibilityLabel("照片处理队列")
                .overlay {
                    if viewModel.jobs.isEmpty { EmptyQueueView() }
                }
                .layoutPriority(1)
                HistorySectionView(viewModel: viewModel)
                statusFooter
            }
            .navigationSplitViewColumnWidth(min: 330, ideal: 390)
        } detail: {
            InspectorView(viewModel: viewModel)
        }
        .toolbar { toolbar }
        .confirmationDialog("选择这台 Mac 的本地推理引擎",
                            isPresented: $viewModel.showEngineSelectionPrompt,
                            titleVisibility: .visible) {
            Button("使用 MLX（推荐）") { viewModel.chooseInferenceEngine(.mlx) }
                .accessibilityHint("针对 Apple 芯片优化；缺少时会继续询问是否自动下载配置")
            Button("使用 Ollama") { viewModel.chooseInferenceEngine(.ollama) }
                .accessibilityHint("继续使用兼容性成熟的 Ollama 本地服务")
            Button("稍后决定", role: .cancel) { viewModel.postponeEngineSelection() }
        } message: {
            Text("MLX 通常在 Apple 芯片上速度更快、能耗更低；Ollama 适合已经安装相关模型的用户。两者都只在本机处理照片，切换不会影响无障碍描述写入。")
        }
        .alert("自动下载并配置本地环境？", isPresented: $viewModel.showRuntimeSetupPrompt) {
            Button("下载并自动配置") { viewModel.acceptRuntimeSetup() }
            Button("暂不下载", role: .cancel) { viewModel.declineRuntimeSetup() }
        } message: {
            Text("检测到缺少：\(viewModel.runtimeSetupReason)。应用只会在您确认后下载 \(viewModel.selectedInferenceEngine.displayName)、ExifTool 或当前视觉模型中缺少的部分；下载后自动安装并校验。模型需要数 GB 空间，建议使用稳定网络。")
        }
    }

    private var queueHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("原始素材")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.jobs.count) 张")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("队列中共有 \(viewModel.jobs.count) 张照片")
            }
            Button(action: viewModel.checkModel) {
                Label(viewModel.modelHealth.label,
                      systemImage: viewModel.modelHealth == .ready ? "checkmark.circle" : "exclamationmark.circle")
            }
            .buttonStyle(.link)
            .accessibilityLabel("本地模型状态")
            .accessibilityValue(viewModel.modelHealth.label)
            .accessibilityHint("重新检查当前推理引擎与视觉模型")
            HStack {
                Button("全选结果") { viewModel.selectAllForWriting() }
                    .disabled(viewModel.jobs.isEmpty || viewModel.isProcessing)
                Button("全部取消") { viewModel.deselectAllForWriting() }
                    .disabled(viewModel.jobs.isEmpty || viewModel.isProcessing)
            }
            Button("清空当前工作区", role: .destructive) {
                viewModel.clearCurrentWorkspace()
            }
            .disabled(viewModel.jobs.isEmpty || viewModel.isProcessing)
            .accessibilityHint("有描述的项目进入历史；只清空软件工作区，不删除磁盘中的照片")
        }
        .padding()
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = viewModel.runtimeProgress {
                Text(progress.step)
                    .font(.callout.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .accessibilityLabel("环境和模型下载进度")
                        .accessibilityValue("百分之 \(Int(fraction * 100))")
                } else {
                    ProgressView()
                        .accessibilityLabel("正在准备环境和模型下载")
                }
                Text(progress.detail)
                    .font(.caption.monospacedDigit())
                    .accessibilityLabel("已处理 \(progress.detail)")
            }
            ProgressView(value: viewModel.displayedProgress)
                .accessibilityLabel("识别与批处理进度")
                .accessibilityValue("百分之 \(Int(viewModel.displayedProgress * 100))")
            Text(viewModel.statusMessage)
                .font(.callout)
                .lineLimit(3)
                .accessibilityLabel("当前状态：\(viewModel.statusMessage)")
        }
        .padding()
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: viewModel.choosePhotos) {
                Label("添加照片", systemImage: "photo.badge.plus")
            }
            .keyboardShortcut("o", modifiers: .command)
            .accessibilityHint("打开文件选择器，可一次选择多张照片")

            Button(action: viewModel.chooseFolder) {
                Label("添加文件夹", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .accessibilityHint("递归扫描文件夹中的支持照片，不会修改文件")

            Button(action: viewModel.startRecognition) {
                Label("开始识别", systemImage: "sparkles")
            }
            .disabled(!viewModel.canRecognize)
            .accessibilityHint("使用本机 \(viewModel.selectedInferenceEngine.displayName) 和 \(viewModel.selectedVisionModel.displayName) 依次生成描述")

            if viewModel.isProcessing {
                Button(role: .cancel, action: viewModel.cancelProcessing) {
                    Label("停止", systemImage: "stop.fill")
                }
                .keyboardShortcut(.cancelAction)
            }

            Button(action: viewModel.removeSelected) {
                Label("删除所选", systemImage: "trash")
            }
            .disabled(!viewModel.canDeleteSelected)
            .keyboardShortcut(.delete, modifiers: .command)
            .accessibilityHint("从当前工作区删除左侧素材和右侧对应结果；原始照片保留在磁盘")

            Button(action: viewModel.chooseExportFolder) {
                Label("批量导出", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(!viewModel.canExport)
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .accessibilityHint("选择目标文件夹，导出所有已选且校对通过的照片副本，并写入及验证无障碍描述")

            Button(action: viewModel.writeSelectedDescriptions) {
                Label("写入原始照片", systemImage: "square.and.arrow.down")
            }
            .disabled(!viewModel.canWrite)
            .accessibilityHint("直接修改已勾选的原始照片；通常建议使用批量导出保留原始素材")

            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .accessibilityHint("打开设置窗口；也可以按 Command-逗号")
        }
    }
}

private struct EmptyQueueView: View {
    var body: some View {
        ContentUnavailableView {
            Label("尚未添加照片", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("按 Command-O 选择一张或多张照片。")
        }
        .accessibilityElement(children: .combine)
    }
}
