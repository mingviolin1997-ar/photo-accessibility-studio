import Foundation

enum JobStatus: String, Codable, CaseIterable {
    case waiting
    case recognizing
    case ready
    case writing
    case completed
    case failed

    var label: String {
        switch self {
        case .waiting: return "等待识别"
        case .recognizing: return "正在识别"
        case .ready: return "等待审核"
        case .writing: return "正在写入"
        case .completed: return "已写入并验证"
        case .failed: return "失败"
        }
    }
}

struct PhotoJob: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    var description: String
    var existingDescription: String?
    var status: JobStatus
    var isApproved: Bool
    var errorMessage: String?
    var generatedStyle: DescriptionStyle?
    var includedCaptureAdvice: Bool?

    init(url: URL) {
        id = UUID()
        self.url = url
        description = ""
        status = .waiting
        isApproved = true
    }

    var displayName: String { url.lastPathComponent }
}
