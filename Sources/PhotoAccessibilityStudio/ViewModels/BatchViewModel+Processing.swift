import Foundation

extension BatchViewModel {
    func checkModel() {
        guard !isRuntimeInstalling else { return }
        guard InferenceEngine.stored() != nil else {
            modelHealth = .unavailable("请先选择 MLX 或 Ollama")
            statusMessage = "请先选择本地推理引擎。推荐 MLX。"
            showEngineSelectionPrompt = true
            return
        }
        modelHealth = .checking
        Task {
            installedModelNames = await installedModelsForCurrentEngine()
            let missing: String?
            switch selectedInferenceEngine {
            case .mlx:
                missing = await mlxRuntimeSetupService.inspect(model: selectedVisionModel)
            case .ollama:
                missing = await runtimeSetupService.inspect(modelName: selectedVisionModel.ollamaName)
            }
            if let missing {
                let previous = RuntimeFailureStore.matching(engine: selectedInferenceEngine,
                                                            model: selectedVisionModel)
                runtimeSetupReason = previous.map {
                    "\(missing)。上次配置未完成：\($0.reason)"
                } ?? missing
                modelHealth = .unavailable(missing)
                statusMessage = previous.map {
                    "上次配置失败：\($0.reason)。当前仍需配置：\(missing)，可以继续下载。"
                } ?? "需要配置：\(missing)。尚未开始下载。"
                showRuntimeSetupPrompt = true
                announce(statusMessage)
            } else {
                modelHealth = .ready
                UserDefaults.standard.removeObject(forKey: "pendingVisionModelID")
                RuntimeFailureStore.clear(engine: selectedInferenceEngine,
                                          model: selectedVisionModel)
                statusMessage = "本地 \(selectedVisionModel.displayName)、\(selectedInferenceEngine.displayName) 与 ExifTool 已就绪。"
            }
        }
    }

    func chooseInferenceEngine(_ engine: InferenceEngine) {
        guard !isProcessing, !isRuntimeInstalling else { return }
        showEngineSelectionPrompt = false
        UserDefaults.standard.set(engine.rawValue, forKey: "selectedInferenceEngine")
        selectedInferenceEngine = engine
        if !selectedVisionModel.supportsPhotoRecognition(on: engine) {
            selectedVisionModel = .qwen35_4B
            UserDefaults.standard.set(VisionModel.qwen35_4B.rawValue,
                                      forKey: "selectedVisionModelID")
        }
        localVisionClient = LocalVisionClient(engine: engine, model: selectedVisionModel)
        installedModelNames = []
        runtimeProgress = nil
        statusMessage = "已选择 \(engine.displayName)，正在检查本机环境。"
        checkModel()
    }

    func acceptRuntimeSetup() {
        guard !isRuntimeInstalling else { return }
        showRuntimeSetupPrompt = false
        isRuntimeInstalling = true
        modelHealth = .checking
        runtimeProgress = RuntimeProgress(step: "正在准备自动配置",
                                          downloaded: 0, total: 0, bytesPerSecond: 0)
        statusMessage = "正在自动下载并配置缺少的本地环境。"
        runtimeInstallTask?.cancel()
        runtimeInstallTask = Task {
            do {
                switch selectedInferenceEngine {
                case .mlx:
                    try await mlxRuntimeSetupService.install(model: selectedVisionModel) { progress in
                        Task { @MainActor in
                            self.runtimeProgress = progress
                            self.statusMessage = progress.step
                        }
                    }
                case .ollama:
                    try await runtimeSetupService.install(modelName: selectedVisionModel.ollamaName) { progress in
                        Task { @MainActor in
                            self.runtimeProgress = progress
                            self.statusMessage = progress.step
                        }
                    }
                }
                isRuntimeInstalling = false
                modelHealth = .ready
                installedModelNames = await installedModelsForCurrentEngine()
                UserDefaults.standard.removeObject(forKey: "pendingVisionModelID")
                RuntimeFailureStore.clear(engine: selectedInferenceEngine,
                                          model: selectedVisionModel)
                statusMessage = "自动配置完成，本地 \(selectedVisionModel.displayName) 与 \(selectedInferenceEngine.displayName) 已就绪。"
                announce(statusMessage)
            } catch is CancellationError {
                isRuntimeInstalling = false
                modelHealth = .unavailable("下载已取消，可从已有进度继续")
                runtimeProgress = RuntimeProgress(step: "下载已取消",
                                                  downloaded: runtimeProgress?.downloaded ?? 0,
                                                  total: runtimeProgress?.total ?? 0,
                                                  bytesPerSecond: 0,
                                                  detailOverride: "已下载文件已保留；点击当前模型即可断点续传")
                statusMessage = "已取消自动配置；现有下载进度已保留，可随时重试。"
                RuntimeFailureStore.save(engine: selectedInferenceEngine,
                                         model: selectedVisionModel,
                                         reason: statusMessage)
                announce(statusMessage)
            } catch {
                isRuntimeInstalling = false
                modelHealth = .unavailable(error.localizedDescription)
                statusMessage = "自动配置失败：\(error.localizedDescription)"
                runtimeProgress = RuntimeProgress(step: "自动配置失败",
                                                  downloaded: runtimeProgress?.downloaded ?? 0,
                                                  total: runtimeProgress?.total ?? 0,
                                                  bytesPerSecond: 0,
                                                  detailOverride: error.localizedDescription)
                RuntimeFailureStore.save(engine: selectedInferenceEngine,
                                         model: selectedVisionModel,
                                         reason: error.localizedDescription)
                AppLogger.shared.error(statusMessage)
                announce(statusMessage)
            }
            runtimeInstallTask = nil
        }
    }

    func refreshInstalledModels() {
        Task {
            installedModelNames = await installedModelsForCurrentEngine()
        }
    }

    func installOrSelect(_ model: VisionModel) {
        guard !isRuntimeInstalling else { return }
        UserDefaults.standard.set(model.rawValue, forKey: "pendingVisionModelID")
        if model.supportsPhotoRecognition(on: selectedInferenceEngine) {
            UserDefaults.standard.set(model.rawValue, forKey: "selectedVisionModelID")
            UserDefaults.standard.set(model.identifier(for: selectedInferenceEngine),
                                      forKey: "selectedVisionModel")
            selectedVisionModel = model
            localVisionClient = LocalVisionClient(engine: selectedInferenceEngine,
                                                  model: model)
        }
        isRuntimeInstalling = true
        installingModelID = model
        runtimeProgress = RuntimeProgress(step: "正在检查 \(model.displayName)",
                                          downloaded: 0,
                                          total: 0,
                                          bytesPerSecond: 0)
        statusMessage = "正在检查本机是否已安装 \(model.displayName)。"
        runtimeInstallTask?.cancel()
        runtimeInstallTask = Task {
            do {
                switch selectedInferenceEngine {
                case .mlx:
                    try await mlxRuntimeSetupService.install(model: model) { progress in
                        Task { @MainActor in
                            self.runtimeProgress = progress
                            self.statusMessage = progress.step
                        }
                    }
                case .ollama:
                    try await runtimeSetupService.install(modelName: model.ollamaName) { progress in
                        Task { @MainActor in
                            self.runtimeProgress = progress
                            self.statusMessage = progress.step
                        }
                    }
                }
                installedModelNames = await installedModelsForCurrentEngine()
                if model.supportsPhotoRecognition(on: selectedInferenceEngine) {
                    UserDefaults.standard.removeObject(forKey: "pendingVisionModelID")
                    modelHealth = .ready
                    statusMessage = "\(model.displayName) 已安装、验证并设为 \(selectedInferenceEngine.displayName) 当前照片识别模型。"
                } else {
                    UserDefaults.standard.removeObject(forKey: "pendingVisionModelID")
                    statusMessage = "\(model.displayName) 已安装；当前 Ollama 包只标注文本输入，因此未替换照片识别模型。移动端请使用 LiteRT-LM 专用版本。"
                }
                RuntimeFailureStore.clear(engine: selectedInferenceEngine, model: model)
                announce(statusMessage)
            } catch is CancellationError {
                modelHealth = .unavailable("下载已取消，可断点续传")
                runtimeProgress = RuntimeProgress(step: "已取消 \(model.displayName) 下载",
                                                  downloaded: runtimeProgress?.downloaded ?? 0,
                                                  total: runtimeProgress?.total ?? 0,
                                                  bytesPerSecond: 0,
                                                  detailOverride: "已有文件已保留；再次点击该模型即可继续")
                statusMessage = "已取消 \(model.displayName) 下载；已有进度已保留。"
                RuntimeFailureStore.save(engine: selectedInferenceEngine,
                                         model: model,
                                         reason: statusMessage)
                announce(statusMessage)
            } catch {
                statusMessage = "\(model.displayName) 配置失败：\(error.localizedDescription)"
                modelHealth = .unavailable(error.localizedDescription)
                runtimeProgress = RuntimeProgress(step: "\(model.displayName) 配置失败",
                                                  downloaded: runtimeProgress?.downloaded ?? 0,
                                                  total: runtimeProgress?.total ?? 0,
                                                  bytesPerSecond: 0,
                                                  detailOverride: error.localizedDescription)
                RuntimeFailureStore.save(engine: selectedInferenceEngine,
                                         model: model,
                                         reason: error.localizedDescription)
                AppLogger.shared.error(statusMessage)
                announce(statusMessage)
            }
            installingModelID = nil
            isRuntimeInstalling = false
            runtimeInstallTask = nil
        }
    }

    func cancelRuntimeInstallation() {
        guard isRuntimeInstalling else { return }
        statusMessage = "正在安全停止下载；已完成的数据会保留。"
        runtimeInstallTask?.cancel()
    }

    func declineRuntimeSetup() {
        showRuntimeSetupPrompt = false
        runtimeProgress = nil
        statusMessage = "已暂不下载。可随时点击模型状态或在设置中重新配置。"
        announce(statusMessage)
    }

    func postponeEngineSelection() {
        showEngineSelectionPrompt = false
        modelHealth = .unavailable("尚未选择推理引擎")
        statusMessage = "已暂不选择。点击模型状态或打开设置即可继续。"
        announce(statusMessage)
    }

    private func installedModelsForCurrentEngine() async -> Set<String> {
        switch selectedInferenceEngine {
        case .mlx: return mlxRuntimeSetupService.installedModelNames()
        case .ollama: return await runtimeSetupService.installedModelNames()
        }
    }

    func startRecognition() {
        guard canRecognize else { return }
        isProcessing = true
        statusMessage = "正在启动本地识别。"
        processingTask = Task {
            let ids = jobs.filter {
                $0.usesSupportedWritableFormat && ($0.status == .waiting || $0.status == .failed)
            }.map(\.id)
            startRecognitionProgress(total: ids.count)
            for (offset, id) in ids.enumerated() {
                guard !Task.isCancelled else { break }
                await recognize(id: id, position: offset + 1, total: ids.count)
                markRecognitionUnitCompleted(offset + 1)
            }
            let recognitionWasCancelled = Task.isCancelled
            finishRecognitionProgress(completed: !recognitionWasCancelled)
            if !Task.isCancelled && UserDefaults.standard.bool(forKey: "autoWriteAfterRecognition") {
                let writeIDs = jobs.filter {
                    $0.status == .ready && $0.isApproved && !$0.description.isEmpty
                }.map(\.id)
                await performWriting(ids: writeIDs)
            }
            isProcessing = false
            processingTask = nil
            statusMessage = Task.isCancelled
                ? "已停止处理。"
                : "识别与自动校对完成。已写入并验证 \(completedCount) 张，待导出或写入 \(readyCount) 张。"
            announce(statusMessage)
        }
    }

    func retrySelected() {
        guard let id = selectionID, !isProcessing,
              jobs.first(where: { $0.id == id })?.usesSupportedWritableFormat == true else { return }
        update(id: id) {
            $0.status = .waiting
            $0.errorMessage = nil
            $0.exportedURL = nil
        }
        startRecognition()
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        recognitionProgressTask?.cancel()
        recognitionProgressTask = nil
        progressSoundPlayer.stop()
    }

    func selectAllForWriting() {
        for index in jobs.indices { jobs[index].isApproved = true }
        statusMessage = "已选择全部 \(jobs.count) 张照片用于批量导出或写入。"
        announce(statusMessage)
    }

    func deselectAllForWriting() {
        for index in jobs.indices { jobs[index].isApproved = false }
        statusMessage = "已取消选择全部照片；批量导出和写入会跳过这些照片。"
        announce(statusMessage)
    }

    func writeSelectedDescriptions() {
        let ids = jobs.filter {
            $0.status == .ready && $0.isApproved && !$0.description.isEmpty
        }.map(\.id)
        beginWriting(ids: ids)
    }

    func requestWriteSelected() {
        guard let id = selectionID,
              let job = selectedJob,
              job.status == .ready,
              job.isApproved,
              !job.description.isEmpty else { return }
        beginWriting(ids: [id])
    }

    private func recognize(id: UUID, position: Int, total: Int) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        update(id: id) { $0.status = .recognizing; $0.errorMessage = nil }
        statusMessage = "正在识别第 \(position) 张，共 \(total) 张。"
        do {
            let preferences = DescriptionPreferences.load()
            let description = try await localVisionClient.describe(
                job.url,
                preferences: preferences
            ) { stage in
                Task { @MainActor in
                    guard self.jobs.first(where: { $0.id == id })?.status == .recognizing else {
                        return
                    }
                    self.statusMessage = "第 \(position) 张，共 \(total) 张：\(stage)。"
                }
            }
            update(id: id) {
                $0.description = description
                $0.generatedStyle = preferences.style
                $0.includedCaptureAdvice = preferences.includeCaptureAdvice
                $0.status = .ready
                $0.exportedURL = nil
            }
        } catch {
            update(id: id) { $0.status = .failed; $0.errorMessage = error.localizedDescription }
            AppLogger.shared.error("识别失败 \(job.displayName)：\(error.localizedDescription)")
        }
    }

    private func beginWriting(ids: [UUID]) {
        guard !ids.isEmpty, !isProcessing else { return }
        isProcessing = true
        processingTask = Task {
            await performWriting(ids: ids)
            isProcessing = false
            statusMessage = Task.isCancelled
                ? "已停止写入。"
                : "写入任务完成。成功 \(completedCount) 张。"
            announce(statusMessage)
        }
    }

    private func performWriting(ids: [UUID]) async {
        for (offset, id) in ids.enumerated() {
            guard !Task.isCancelled,
                  let job = jobs.first(where: { $0.id == id }) else { break }
            update(id: id) { $0.status = .writing; $0.errorMessage = nil }
            let sequence = (jobs.firstIndex(where: { $0.id == id }) ?? offset) + 1
            statusMessage = "正在写入第 \(sequence) 张照片；本批共 \(ids.count) 张。"
            do {
                let writer = metadataWriter
                _ = try await Task.detached {
                    try writer.write(job.description, to: job.url)
                }.value
                update(id: id) {
                    $0.status = .completed
                    $0.existingDescription = $0.description
                    $0.exportedURL = nil
                }
            } catch {
                update(id: id) { $0.status = .failed; $0.errorMessage = error.localizedDescription }
                AppLogger.shared.error("写入失败 \(job.displayName)：\(error.localizedDescription)")
            }
        }
    }

    private func startRecognitionProgress(total: Int) {
        recognitionProgressTask?.cancel()
        recognitionCompletedUnits = 0
        recognitionTotalUnits = max(total, 1)
        recognitionProgress = 0
        let soundEnabled = UserDefaults.standard.object(forKey: "progressSoundEnabled") as? Bool ?? true
        progressSoundPlayer.start(enabled: soundEnabled)
        recognitionProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self,
                      let current = self.recognitionProgress else { break }
                let nextUnit = min(self.recognitionCompletedUnits + 1,
                                   self.recognitionTotalUnits)
                let ceiling = min(Double(nextUnit) / Double(self.recognitionTotalUnits), 0.98)
                guard current < ceiling else { continue }
                let next = min(ceiling, current + max(0.006, (ceiling - current) * 0.12))
                self.recognitionProgress = next
                self.progressSoundPlayer.update(progress: next)
            }
        }
    }

    private func markRecognitionUnitCompleted(_ completed: Int) {
        recognitionCompletedUnits = min(completed, recognitionTotalUnits)
        let progress = Double(recognitionCompletedUnits) / Double(recognitionTotalUnits)
        recognitionProgress = progress
        progressSoundPlayer.update(progress: progress)
    }

    private func finishRecognitionProgress(completed: Bool) {
        recognitionProgressTask?.cancel()
        recognitionProgressTask = nil
        if completed {
            recognitionProgress = 1
            progressSoundPlayer.update(progress: 1)
            progressSoundPlayer.complete()
        } else {
            progressSoundPlayer.stop()
            recognitionProgress = nil
        }
    }
}
