import AppKit
import SwiftUI

struct InspectorView: View {
    @ObservedObject var viewModel: BatchViewModel
    @State private var expandedEditors: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            resultHeader
            if viewModel.resultJobs.isEmpty {
                ContentUnavailableView {
                    Label("尚无识别结果", systemImage: "text.below.photo")
                } description: {
                    Text("开始识别后，校对通过的描述会在这里逐张列出。")
                }
                .accessibilityElement(children: .combine)
            } else {
                List(viewModel.resultJobs, selection: $viewModel.selectionID) { job in
                    ResultPhotoView(
                        job: job,
                        description: viewModel.bindingForDescription(id: job.id),
                        isEditorExpanded: editorBinding(for: job.id),
                        isProcessing: viewModel.isProcessing,
                        retry: {
                            viewModel.selectionID = job.id
                            viewModel.retrySelected()
                        },
                        writeOriginal: {
                            viewModel.selectionID = job.id
                            viewModel.requestWriteSelected()
                        },
                        reveal: {
                            viewModel.selectionID = job.id
                            viewModel.revealSelected()
                        },
                        remove: {
                            viewModel.selectionID = job.id
                            viewModel.removeSelected()
                        }
                    )
                    .tag(job.id)
                }
                .listStyle(.inset)
                .accessibilityLabel("识别和无障碍描述结果列表")
                .accessibilityHint("聚焦列表后，使用上、下方向键逐张浏览；编辑框默认隐藏")
            }
        }
        .navigationTitle("识别与描述结果")
    }

    private var resultHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("识别结果")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("共 \(viewModel.resultJobs.count) 项；描述只有通过自动校对后才显示。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("批量导出已选结果…") {
                viewModel.chooseExportFolder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canExport)
            .accessibilityHint("选择目标文件夹，生成真正写入并验证无障碍描述的照片副本")
        }
        .padding()
        .background(.bar)
    }

    private func editorBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedEditors.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedEditors.insert(id)
                } else {
                    expandedEditors.remove(id)
                }
            }
        )
    }
}

private struct ResultPhotoView: View {
    let job: PhotoJob
    @Binding var description: String
    @Binding var isEditorExpanded: Bool
    let isProcessing: Bool
    let retry: () -> Void
    let writeOriginal: () -> Void
    let reveal: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.displayName)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text("状态：\(job.status.label)")
                        .foregroundStyle(statusColor)
                    if let style = job.generatedStyle {
                        Text("\(style.label)\(job.includedCaptureAdvice == true ? "，含拍摄建议" : "")")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack {
                Text("无障碍描述")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(isEditorExpanded ? "收起编辑" : "编辑") {
                    isEditorExpanded.toggle()
                }
                .disabled(description.isEmpty || isProcessing)
                .accessibilityHint(isEditorExpanded
                    ? "隐藏文字输入区域，保留当前修改"
                    : "展开文字输入区域，以便手动微调描述")
            }

            if description.isEmpty {
                Text(emptyDescriptionMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(emptyDescriptionMessage)
            } else {
                Text(description)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityLabel("无障碍描述：\(description)")
            }

            if isEditorExpanded {
                TextEditor(text: $description)
                    .font(.body)
                    .frame(minHeight: 130)
                    .padding(5)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    .accessibilityLabel("编辑 \(job.displayName) 的无障碍描述")
                    .accessibilityHint("修改后需要重新批量导出或写入原始照片，系统才会验证新内容")
            }

            if let error = job.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .accessibilityLabel("错误：\(error)")
            }

            HStack {
                Button("重新识别", action: retry)
                    .disabled(isProcessing)
                Button("写入原始照片", action: writeOriginal)
                    .disabled(isProcessing || job.status != .ready || description.isEmpty)
                    .accessibilityHint("直接修改原始素材；如需保留原图，请使用批量导出")
                Button("在 Finder 中显示", action: reveal)
                Spacer()
                Button("从队列移除", role: .destructive, action: remove)
                    .disabled(isProcessing)
                    .accessibilityHint("只移除队列记录，不删除照片")
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var preview: some View {
        if let image = NSImage(contentsOf: job.url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 120)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(description.isEmpty
                    ? "照片预览，文件名 \(job.displayName)"
                    : description)
        }
    }

    private var emptyDescriptionMessage: String {
        if job.status == .failed {
            return "识别或校对失败，没有显示未经校验的描述。"
        }
        return "正在识别和校对；通过后将在这里显示描述。"
    }

    private var statusColor: Color {
        switch job.status {
        case .completed, .exported: return .green
        case .failed: return .red
        case .recognizing, .writing: return .blue
        default: return .secondary
        }
    }
}
