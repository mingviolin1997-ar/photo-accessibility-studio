import AppKit
import SwiftUI

struct InspectorView: View {
    @ObservedObject var viewModel: BatchViewModel

    var body: some View {
        Group {
            if let job = viewModel.selectedJob {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(job)
                        preview(job)
                        existingDescription(job)
                        editor(job)
                        errorMessage(job)
                        actions(job)
                    }
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .leading)
                }
            } else {
                ContentUnavailableView("请选择照片", systemImage: "sidebar.left")
                    .accessibilityLabel("尚未选择照片")
            }
        }
        .navigationTitle(viewModel.selectedJob?.displayName ?? "无障碍照片描述")
    }

    private func header(_ job: PhotoJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(job.displayName)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            Text("状态：\(job.status.label)")
                .foregroundStyle(job.status == .failed ? .red : .secondary)
            if let style = job.generatedStyle {
                Text("生成模式：\(style.label)\(job.includedCaptureAdvice == true ? "，含拍摄建议" : "")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func preview(_ job: PhotoJob) -> some View {
        if let image = NSImage(contentsOf: job.url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(job.description.isEmpty
                    ? "待识别照片预览，文件名 \(job.displayName)"
                    : job.description)
        }
    }

    @ViewBuilder
    private func existingDescription(_ job: PhotoJob) -> some View {
        if let existing = job.existingDescription, !existing.isEmpty {
            GroupBox("照片中现有的 Image Description") {
                Text(existing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 6)
            }
            .accessibilityHint("写入新描述后，此内容将被替换")
        }
    }

    private func editor(_ job: PhotoJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("生成的无障碍描述")
                .font(.headline)
            TextEditor(text: viewModel.bindingForDescription(id: job.id))
                .font(.body)
                .frame(minHeight: 150)
                .padding(5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .accessibilityLabel("生成的无障碍描述，可编辑")
                .accessibilityHint("可选编辑；默认会自动写入已选照片")
            Toggle("写入此照片", isOn: viewModel.bindingForApproval(id: job.id))
                .accessibilityHint("默认选中；取消后自动写入和批量写入都会跳过这张照片")
        }
    }

    @ViewBuilder
    private func errorMessage(_ job: PhotoJob) -> some View {
        if let error = job.errorMessage {
            GroupBox("错误详情") {
                Text(error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .foregroundStyle(.red)
        }
    }

    private func actions(_ job: PhotoJob) -> some View {
        HStack {
            Button("重新识别") { viewModel.retrySelected() }
                .disabled(viewModel.isProcessing)
            Button("写入此照片") { viewModel.requestWriteSelected() }
                .disabled(viewModel.isProcessing || job.status != .ready ||
                          !job.isApproved || job.description.isEmpty)
            Button("在 Finder 中显示") { viewModel.revealSelected() }
            Spacer()
            Button("从队列移除", role: .destructive) { viewModel.removeSelected() }
                .disabled(viewModel.isProcessing)
                .accessibilityHint("只移除队列记录，不会删除原照片")
        }
        .controlSize(.large)
    }
}
