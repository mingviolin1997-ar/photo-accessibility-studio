import AppKit
import Foundation

extension BatchViewModel {
    func chooseExportFolder() {
        guard canExport else { return }
        let panel = NSOpenPanel()
        panel.title = "选择无障碍照片的导出文件夹"
        panel.prompt = "导出到这里"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        exportSelectedResults(to: folder)
    }

    private func exportSelectedResults(to folder: URL) {
        let ids = jobs.filter {
            $0.isApproved && !$0.description.isEmpty &&
            [.ready, .completed, .exported, .failed].contains($0.status)
        }.map(\.id)
        guard !ids.isEmpty, !isProcessing else { return }

        isProcessing = true
        processingTask = Task {
            var successCount = 0
            var failureCount = 0
            for (offset, id) in ids.enumerated() {
                guard !Task.isCancelled,
                      let job = jobs.first(where: { $0.id == id }) else { break }
                let previousStatus = job.status
                update(id: id) {
                    $0.status = .writing
                    $0.errorMessage = nil
                }
                let sequence = (jobs.firstIndex(where: { $0.id == id }) ?? offset) + 1
                statusMessage = "正在导出并验证第 \(sequence) 张照片；本批共 \(ids.count) 张。"
                do {
                    let service = batchExportService
                    let exported = try await Task.detached {
                        try service.export(description: job.description,
                                           from: job.url,
                                           to: folder)
                    }.value
                    successCount += 1
                    update(id: id) {
                        $0.status = .exported
                        $0.exportedURL = exported.outputURL
                        $0.errorMessage = nil
                    }
                } catch {
                    failureCount += 1
                    update(id: id) {
                        $0.status = previousStatus == .completed || previousStatus == .exported
                            ? previousStatus : .ready
                        $0.errorMessage = "导出失败：\(error.localizedDescription)"
                    }
                    AppLogger.shared.error("导出失败 \(job.displayName)：\(error.localizedDescription)")
                }
            }
            isProcessing = false
            processingTask = nil
            if Task.isCancelled {
                statusMessage = "已停止批量导出。成功导出 \(successCount) 张。"
            } else {
                statusMessage = "批量导出完成：成功 \(successCount) 张，失败 \(failureCount) 张。导出文件均已写入并通过底层验证。"
            }
            announce(statusMessage)
        }
    }
}
