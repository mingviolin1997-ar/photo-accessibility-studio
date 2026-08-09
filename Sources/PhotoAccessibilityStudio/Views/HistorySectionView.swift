import AppKit
import SwiftUI

struct HistorySectionView: View {
    @ObservedObject var viewModel: BatchViewModel
    @AppStorage("historyRetentionDays") private var retentionDays = 30
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("自动保留 \(retentionDays) 天")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空历史", role: .destructive) {
                        viewModel.clearHistory()
                    }
                    .disabled(viewModel.historyBatches.isEmpty)
                    .accessibilityHint("只清除软件记录，不删除磁盘中的照片")
                }
                if viewModel.historyBatches.isEmpty {
                    Text("暂无历史记录")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(viewModel.historyBatches) { batch in
                                HistoryBatchView(batch: batch,
                                                 deleteBatch: {
                                                     viewModel.deleteHistoryBatch(id: batch.id)
                                                 },
                                                 deleteItem: { jobID in
                                                     viewModel.deleteHistoryItem(batchID: batch.id,
                                                                                 jobID: jobID)
                                                 })
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .accessibilityLabel("历史照片批次")
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Label("历史记录", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.historyPhotoCount) 张")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityHint("默认折叠；展开后可查看或清除最近的描述记录")
    }
}

private struct HistoryBatchView: View {
    let batch: HistoryBatch
    let deleteBatch: () -> Void
    let deleteItem: (UUID) -> Void
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(batch.jobs) { job in
                    HStack(alignment: .top, spacing: 8) {
                        thumbnail(for: job)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.displayName)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(job.description)
                                .font(.caption)
                                .lineLimit(3)
                            if !FileManager.default.fileExists(atPath: job.url.path) {
                                Text("原照片位置当前不可用")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            deleteItem(job.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("删除 \(job.displayName) 的历史记录")
                        .accessibilityHint("不删除磁盘中的照片")
                    }
                    .accessibilityElement(children: .contain)
                }
                Button("删除此历史批次", role: .destructive, action: deleteBatch)
                    .accessibilityHint("只删除软件历史记录，不删除磁盘中的照片")
            }
            .padding(.leading, 12)
            .padding(.top, 6)
        } label: {
            Text("\(batch.name)，\(batch.jobs.count) 张")
                .font(.callout)
                .accessibilityLabel("历史批次 \(batch.name)，包含 \(batch.jobs.count) 张照片")
        }
    }

    @ViewBuilder
    private func thumbnail(for job: PhotoJob) -> some View {
        if let image = NSImage(contentsOf: job.url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .accessibilityLabel(job.description)
        } else {
            Image(systemName: "photo")
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
        }
    }
}
