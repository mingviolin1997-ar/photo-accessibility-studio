import AppKit
import Foundation

extension BatchViewModel {
    func removeSelected() {
        guard !isProcessing, let id = selectionID,
              let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let removed = jobs[index]
        archiveInHistory([removed])
        jobs.remove(at: index)
        selectionID = jobs.indices.contains(index) ? jobs[index].id : jobs.last?.id
        statusMessage = removed.description.isEmpty
            ? "已从当前工作区移除素材和对应结果；磁盘中的原始照片未删除。"
            : "已从当前工作区移除素材和对应结果，并保存到历史；磁盘中的原始照片未删除。"
        announce(statusMessage)
    }

    func clearCurrentWorkspace() {
        guard !isProcessing, !jobs.isEmpty else { return }
        let count = jobs.count
        archiveInHistory(jobs)
        jobs.removeAll()
        selectionID = nil
        recognitionProgress = nil
        statusMessage = "已清空当前工作区的 \(count) 项；有描述的项目已进入历史，磁盘中的照片未删除。"
        announce(statusMessage)
    }

    func clearHistory() {
        guard !historyBatches.isEmpty else { return }
        historyBatches.removeAll()
        statusMessage = "已清空软件历史记录；原始照片和已导出文件未删除。"
        announce(statusMessage)
    }

    func deleteHistoryBatch(id: UUID) {
        historyBatches.removeAll { $0.id == id }
        statusMessage = "已删除所选历史批次；磁盘中的照片未删除。"
        announce(statusMessage)
    }

    func deleteHistoryItem(batchID: UUID, jobID: UUID) {
        guard let batchIndex = historyBatches.firstIndex(where: { $0.id == batchID }) else {
            return
        }
        historyBatches[batchIndex].jobs.removeAll { $0.id == jobID }
        if historyBatches[batchIndex].jobs.isEmpty {
            historyBatches.remove(at: batchIndex)
        }
        statusMessage = "已删除所选历史记录；磁盘中的照片未删除。"
        announce(statusMessage)
    }

    func applyHistoryRetention(days: Int) {
        let before = historyPhotoCount
        historyBatches = HistoryBatch.retaining(historyBatches, days: days)
        let removed = before - historyPhotoCount
        if removed > 0 {
            statusMessage = "已自动清理 \(removed) 条超过 \(days) 天的软件历史记录；磁盘中的照片未删除。"
            announce(statusMessage)
        }
    }

    func revealSelected() {
        guard let url = selectedJob?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func update(id: UUID, mutate: (inout PhotoJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }

    private func archiveInHistory(_ candidates: [PhotoJob]) {
        let described = candidates.filter { !$0.description.isEmpty }
        guard !described.isEmpty else { return }
        historyBatches.insert(HistoryBatch(jobs: described), at: 0)
        let days = UserDefaults.standard.object(forKey: "historyRetentionDays") == nil
            ? 30 : UserDefaults.standard.integer(forKey: "historyRetentionDays")
        historyBatches = HistoryBatch.retaining(historyBatches, days: days)
    }

    func announce(_ message: String) {
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
