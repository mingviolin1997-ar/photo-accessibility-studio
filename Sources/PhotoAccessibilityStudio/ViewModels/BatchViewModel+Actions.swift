import AppKit
import Foundation

extension BatchViewModel {
    func removeSelected() {
        guard !isProcessing, let id = selectionID,
              let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs.remove(at: index)
        selectionID = jobs.indices.contains(index) ? jobs[index].id : jobs.last?.id
        statusMessage = "已从队列移除；原照片未删除。"
        announce(statusMessage)
    }

    func revealSelected() {
        guard let url = selectedJob?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func update(id: UUID, mutate: (inout PhotoJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }

    func announce(_ message: String) {
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
