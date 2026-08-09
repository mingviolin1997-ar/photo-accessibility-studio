import Foundation

extension BatchViewModel {
    func checkModel() {
        guard !isRuntimeInstalling else { return }
        modelHealth = .checking
        Task {
            installedModelNames = await runtimeSetupService.installedModelNames()
            let modelName = ollamaClient.configuration.modelName
            if let missing = await runtimeSetupService.inspect(modelName: modelName) {
                runtimeSetupReason = missing
                modelHealth = .unavailable(missing)
                statusMessage = "需要配置：\(missing)。尚未开始下载。"
                showRuntimeSetupPrompt = true
                announce(statusMessage)
            } else {
                modelHealth = .ready
                statusMessage = "本地 \(selectedVisionModel.displayName)、Ollama 与 ExifTool 已就绪。"
            }
        }
    }

    func acceptRuntimeSetup() {
        guard !isRuntimeInstalling else { return }
        showRuntimeSetupPrompt = false
        isRuntimeInstalling = true
        modelHealth = .checking
        runtimeProgress = RuntimeProgress(step: "正在准备自动配置",
                                          downloaded: 0, total: 0, bytesPerSecond: 0)
        statusMessage = "正在自动下载并配置缺少的本地环境。"
        Task {
            do {
                let modelName = ollamaClient.configuration.modelName
                try await runtimeSetupService.install(modelName: modelName) { progress in
                    Task { @MainActor in
                        self.runtimeProgress = progress
                        self.statusMessage = progress.step
                    }
                }
                isRuntimeInstalling = false
                modelHealth = .ready
                installedModelNames = await runtimeSetupService.installedModelNames()
                statusMessage = "自动配置完成，本地 \(selectedVisionModel.displayName) 已就绪。"
                announce(statusMessage)
            } catch {
                isRuntimeInstalling = false
                modelHealth = .unavailable(error.localizedDescription)
                statusMessage = "自动配置失败：\(error.localizedDescription)"
                announce(statusMessage)
            }
        }
    }

    func refreshInstalledModels() {
        Task {
            installedModelNames = await runtimeSetupService.installedModelNames()
        }
    }

    func installOrSelect(_ model: VisionModel) {
        guard !isRuntimeInstalling else { return }
        isRuntimeInstalling = true
        installingModelID = model
        runtimeProgress = RuntimeProgress(step: "正在检查 \(model.displayName)",
                                          downloaded: 0,
                                          total: 0,
                                          bytesPerSecond: 0)
        statusMessage = "正在检查本机是否已安装 \(model.displayName)。"
        Task {
            do {
                try await runtimeSetupService.install(modelName: model.ollamaName) { progress in
                    Task { @MainActor in
                        self.runtimeProgress = progress
                        self.statusMessage = progress.step
                    }
                }
                installedModelNames = await runtimeSetupService.installedModelNames()
                if model.supportsPhotoRecognitionInMacApp {
                    UserDefaults.standard.set(model.ollamaName, forKey: "selectedVisionModel")
                    ollamaClient = OllamaClient(configuration: AppConfiguration(modelName: model.ollamaName))
                    modelHealth = .ready
                    statusMessage = installedModelNames.contains(model.ollamaName)
                        ? "\(model.displayName) 已安装、验证并设为当前照片识别模型。"
                        : "\(model.displayName) 已验证并设为当前照片识别模型。"
                } else {
                    statusMessage = "\(model.displayName) 已安装；当前 Ollama 包只标注文本输入，因此未替换照片识别模型。移动端请使用 LiteRT-LM 专用版本。"
                }
                announce(statusMessage)
            } catch {
                statusMessage = "\(model.displayName) 配置失败：\(error.localizedDescription)"
                announce(statusMessage)
            }
            installingModelID = nil
            isRuntimeInstalling = false
        }
    }

    func declineRuntimeSetup() {
        showRuntimeSetupPrompt = false
        runtimeProgress = nil
        statusMessage = "已暂不下载。可随时点击模型状态或在设置中重新配置。"
        announce(statusMessage)
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
            let description = try await ollamaClient.describe(
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
