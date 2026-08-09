import Foundation
import SwiftUI

enum ModelHealth: Equatable {
    case checking
    case ready
    case unavailable(String)

    var label: String {
        switch self {
        case .checking: return "正在检查本地模型"
        case .ready: return "Qwen 3.5 4B 已连接"
        case let .unavailable(message): return "模型不可用：\(message)"
        }
    }
}

@MainActor
final class BatchViewModel: ObservableObject {
    @Published var jobs: [PhotoJob] {
        didSet { stateStore.save(jobs) }
    }
    @Published var selectionID: UUID?
    @Published var isProcessing = false
    @Published var statusMessage = "请选择照片开始。所有识别都在本机完成。"
    @Published var isSettingsPresented = false
    @Published var modelHealth: ModelHealth = .checking

    let ollamaClient: OllamaClient
    let metadataWriter: MetadataWriter
    let stateStore: StateStore
    var processingTask: Task<Void, Never>?

    init(ollamaClient: OllamaClient = .init(),
         metadataWriter: MetadataWriter = .init(),
         stateStore: StateStore = .init()) {
        self.ollamaClient = ollamaClient
        self.metadataWriter = metadataWriter
        self.stateStore = stateStore
        jobs = stateStore.load().map { job in
            var recovered = job
            if recovered.status == .recognizing { recovered.status = .waiting }
            if recovered.status == .writing { recovered.status = .ready }
            if recovered.status == .waiting && recovered.description.isEmpty {
                recovered.isApproved = true
            }
            return recovered
        }
        selectionID = jobs.first?.id
        checkModel()
    }

    var selectedJob: PhotoJob? { jobs.first { $0.id == selectionID } }

    var canRecognize: Bool {
        modelHealth == .ready && !isProcessing &&
        jobs.contains { $0.status == .waiting || $0.status == .failed }
    }

    var canWrite: Bool {
        !isProcessing && jobs.contains {
            $0.status == .ready && $0.isApproved && !$0.description.isEmpty
        }
    }

    var completedCount: Int { jobs.filter { $0.status == .completed }.count }
    var readyCount: Int { jobs.filter { $0.status == .ready }.count }

    var overallProgress: Double {
        guard !jobs.isEmpty else { return 0 }
        let handled = jobs.filter { [.ready, .completed, .failed].contains($0.status) }.count
        return Double(handled) / Double(jobs.count)
    }

    func bindingForDescription(id: UUID) -> Binding<String> {
        Binding(
            get: { self.jobs.first { $0.id == id }?.description ?? "" },
            set: { value in self.update(id: id) { $0.description = value } }
        )
    }

    func bindingForApproval(id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.jobs.first { $0.id == id }?.isApproved ?? false },
            set: { value in self.update(id: id) { $0.isApproved = value } }
        )
    }
}
