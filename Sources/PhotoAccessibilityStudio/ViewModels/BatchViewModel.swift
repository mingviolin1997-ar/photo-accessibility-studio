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
    @Published var historyBatches: [HistoryBatch] {
        didSet { stateStore.saveHistory(historyBatches) }
    }
    @Published var selectionID: UUID?
    @Published var isProcessing = false
    @Published var statusMessage = "请选择照片开始。所有识别都在本机完成。"
    @Published var isSettingsPresented = false
    @Published var modelHealth: ModelHealth = .checking
    @Published var showRuntimeSetupPrompt = false
    @Published var runtimeSetupReason = ""
    @Published var runtimeProgress: RuntimeProgress?
    @Published var isRuntimeInstalling = false
    @Published var recognitionProgress: Double?

    let ollamaClient: OllamaClient
    let metadataWriter: MetadataWriter
    let batchExportService: BatchExportService
    let stateStore: StateStore
    let runtimeSetupService: RuntimeSetupService
    let progressSoundPlayer: ProgressSoundPlayer
    var processingTask: Task<Void, Never>?
    var recognitionProgressTask: Task<Void, Never>?
    var recognitionCompletedUnits = 0
    var recognitionTotalUnits = 0

    init(ollamaClient: OllamaClient = .init(),
         metadataWriter: MetadataWriter = .init(),
         stateStore: StateStore = .init(),
         runtimeSetupService: RuntimeSetupService? = nil,
         batchExportService: BatchExportService? = nil,
         progressSoundPlayer: ProgressSoundPlayer? = nil) {
        self.ollamaClient = ollamaClient
        self.metadataWriter = metadataWriter
        self.batchExportService = batchExportService ?? BatchExportService(
            metadataWriter: metadataWriter
        )
        self.stateStore = stateStore
        self.runtimeSetupService = runtimeSetupService ?? RuntimeSetupService(ollamaClient: ollamaClient)
        self.progressSoundPlayer = progressSoundPlayer ?? ProgressSoundPlayer()
        let recoveredJobs = stateStore.load().map { job in
            var recovered = job
            if recovered.status == .recognizing { recovered.status = .waiting }
            if recovered.status == .writing { recovered.status = .ready }
            if recovered.status == .waiting && recovered.description.isEmpty {
                recovered.isApproved = true
            }
            return recovered
        }
        let storedDays = UserDefaults.standard.object(forKey: "historyRetentionDays") == nil
            ? 30 : UserDefaults.standard.integer(forKey: "historyRetentionDays")
        var recoveredHistory = stateStore.loadHistory(retentionDays: storedDays)
        let previousDescribed = recoveredJobs.filter { !$0.description.isEmpty }
        if !previousDescribed.isEmpty {
            recoveredHistory.insert(HistoryBatch(jobs: previousDescribed), at: 0)
        }
        recoveredHistory = HistoryBatch.retaining(recoveredHistory, days: storedDays)
        jobs = []
        historyBatches = recoveredHistory
        stateStore.save([])
        stateStore.saveHistory(recoveredHistory)
        selectionID = nil
        checkModel()
    }

    var selectedJob: PhotoJob? { jobs.first { $0.id == selectionID } }
    var canDeleteSelected: Bool { !isProcessing && selectedJob != nil }
    var historyPhotoCount: Int {
        historyBatches.reduce(0) { $0 + $1.jobs.count }
    }

    var canRecognize: Bool {
        modelHealth == .ready && !isProcessing && !isRuntimeInstalling &&
        jobs.contains { $0.status == .waiting || $0.status == .failed }
    }

    var canWrite: Bool {
        !isProcessing && jobs.contains {
            $0.status == .ready && $0.isApproved && !$0.description.isEmpty
        }
    }

    var canExport: Bool {
        !isProcessing && jobs.contains {
            $0.isApproved && !$0.description.isEmpty &&
            [.ready, .completed, .exported, .failed].contains($0.status)
        }
    }

    var resultJobs: [PhotoJob] {
        jobs.filter { $0.status != .waiting || !$0.description.isEmpty }
    }

    var completedCount: Int {
        jobs.filter { $0.status == .completed || $0.status == .exported }.count
    }
    var readyCount: Int { jobs.filter { $0.status == .ready }.count }

    var overallProgress: Double {
        guard !jobs.isEmpty else { return 0 }
        let handled = jobs.filter {
            [.ready, .completed, .exported, .failed].contains($0.status)
        }.count
        return Double(handled) / Double(jobs.count)
    }

    var displayedProgress: Double {
        recognitionProgress ?? overallProgress
    }

    func bindingForDescription(id: UUID) -> Binding<String> {
        Binding(
            get: { self.jobs.first { $0.id == id }?.description ?? "" },
            set: { value in
                self.update(id: id) {
                    $0.description = value
                    $0.errorMessage = nil
                    if $0.status == .completed || $0.status == .exported {
                        $0.status = .ready
                        $0.exportedURL = nil
                    }
                }
            }
        )
    }

    func bindingForApproval(id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.jobs.first { $0.id == id }?.isApproved ?? false },
            set: { value in self.update(id: id) { $0.isApproved = value } }
        )
    }
}
