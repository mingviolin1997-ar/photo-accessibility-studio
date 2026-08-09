import Foundation
import SwiftUI

enum ModelHealth: Equatable {
    case checking
    case ready
    case unavailable(String)

    var label: String {
        switch self {
        case .checking: return "正在检查本地模型"
        case .ready: return "本地视觉模型已连接"
        case let .unavailable(message): return "模型不可用：\(message)"
        }
    }
}

struct NumberedPhotoJob: Identifiable {
    let sequence: Int
    let job: PhotoJob
    var id: UUID { job.id }
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
    @Published var modelHealth: ModelHealth = .checking
    @Published var showRuntimeSetupPrompt = false
    @Published var showEngineSelectionPrompt = false
    @Published var runtimeSetupReason = ""
    @Published var runtimeProgress: RuntimeProgress?
    @Published var isRuntimeInstalling = false
    @Published var recognitionProgress: Double?
    @Published var installedModelNames: Set<String> = []
    @Published var installingModelID: VisionModel?
    @Published var selectedInferenceEngine: InferenceEngine
    @Published var selectedVisionModel: VisionModel

    var localVisionClient: LocalVisionClient
    let metadataWriter: MetadataWriter
    let batchExportService: BatchExportService
    let stateStore: StateStore
    let runtimeSetupService: RuntimeSetupService
    let mlxRuntimeSetupService: MLXRuntimeSetupService
    let progressSoundPlayer: ProgressSoundPlayer
    var processingTask: Task<Void, Never>?
    var runtimeInstallTask: Task<Void, Never>?
    var recognitionProgressTask: Task<Void, Never>?
    var recognitionCompletedUnits = 0
    var recognitionTotalUnits = 0

    init(metadataWriter: MetadataWriter = .init(),
         stateStore: StateStore = .init(),
         runtimeSetupService: RuntimeSetupService? = nil,
         mlxRuntimeSetupService: MLXRuntimeSetupService? = nil,
         batchExportService: BatchExportService? = nil,
         progressSoundPlayer: ProgressSoundPlayer? = nil) {
        let defaults = UserDefaults.standard
        let storedEngine = InferenceEngine.stored(defaults: defaults)
        let engine = storedEngine ?? .mlx
        let pendingModel = defaults.string(forKey: "pendingVisionModelID")
            .flatMap(VisionModel.matching(identifier:))
        let recoveredIncompleteModel = engine == .mlx
            ? MLXRuntimeSetupService.mostRecentIncompleteModel() : nil
        let model = pendingModel ?? recoveredIncompleteModel ?? VisionModel.stored(defaults: defaults)
        if pendingModel != nil || recoveredIncompleteModel != nil {
            defaults.set(model.rawValue, forKey: "pendingVisionModelID")
            defaults.set(model.rawValue, forKey: "selectedVisionModelID")
            defaults.set(model.identifier(for: engine), forKey: "selectedVisionModel")
        }
        self.selectedInferenceEngine = engine
        self.selectedVisionModel = model
        self.localVisionClient = LocalVisionClient(engine: engine, model: model)
        self.metadataWriter = metadataWriter
        self.batchExportService = batchExportService ?? BatchExportService(
            metadataWriter: metadataWriter
        )
        self.stateStore = stateStore
        let ollamaRuntime = runtimeSetupService ?? RuntimeSetupService()
        self.runtimeSetupService = ollamaRuntime
        self.mlxRuntimeSetupService = mlxRuntimeSetupService
            ?? MLXRuntimeSetupService(metadataSetupService: ollamaRuntime)
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
        if storedEngine == nil {
            modelHealth = .unavailable("请先选择 MLX 或 Ollama")
            statusMessage = "首次在 Mac 上运行，请选择本地推理引擎。推荐 MLX。"
            showEngineSelectionPrompt = true
        } else {
            checkModel()
        }
    }

    var selectedJob: PhotoJob? { jobs.first { $0.id == selectionID } }
    var currentModelIdentifier: String {
        selectedVisionModel.identifier(for: selectedInferenceEngine)
    }
    var canDeleteSelected: Bool { !isProcessing && selectedJob != nil }
    var historyPhotoCount: Int {
        historyBatches.reduce(0) { $0 + $1.jobs.count }
    }

    var canRecognize: Bool {
        modelHealth == .ready && !isProcessing && !isRuntimeInstalling &&
        jobs.contains {
            $0.usesSupportedWritableFormat && ($0.status == .waiting || $0.status == .failed)
        }
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

    var numberedResultJobs: [NumberedPhotoJob] {
        jobs.enumerated().compactMap { offset, job in
            guard job.status != .waiting || !job.description.isEmpty else { return nil }
            return NumberedPhotoJob(sequence: offset + 1, job: job)
        }
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
