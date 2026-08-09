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
                statusFooter
            }
            .navigationSplitViewColumnWidth(min: 330, ideal: 390)
        } detail: {
            InspectorView(viewModel: viewModel)
        }
        .toolbar { toolbar }
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsView()
        }
    }

    private var queueHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("照片队列")
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
            .accessibilityHint("重新检查 Ollama 与 Qwen 模型")
            HStack {
                Button("全选写入") { viewModel.selectAllForWriting() }
                    .disabled(viewModel.jobs.isEmpty || viewModel.isProcessing)
                Button("全部取消") { viewModel.deselectAllForWriting() }
                    .disabled(viewModel.jobs.isEmpty || viewModel.isProcessing)
            }
        }
        .padding()
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: viewModel.overallProgress)
                .accessibilityLabel("批处理进度")
                .accessibilityValue("百分之 \(Int(viewModel.overallProgress * 100))")
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
            .accessibilityHint("使用本机 Qwen 模型依次生成描述")

            if viewModel.isProcessing {
                Button(role: .cancel, action: viewModel.cancelProcessing) {
                    Label("停止", systemImage: "stop.fill")
                }
                .keyboardShortcut(.cancelAction)
            }

            Button(action: viewModel.selectAllForWriting) {
                Label("全选写入", systemImage: "checkmark.circle")
            }
            .disabled(viewModel.jobs.isEmpty || viewModel.isProcessing)

            Button(action: viewModel.writeSelectedDescriptions) {
                Label("写入已选照片", systemImage: "square.and.arrow.down")
            }
            .disabled(!viewModel.canWrite)
            .accessibilityHint("立即写入已勾选且已经生成描述的照片")

            Button { viewModel.isSettingsPresented = true } label: {
                Label("设置", systemImage: "gearshape")
            }
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
