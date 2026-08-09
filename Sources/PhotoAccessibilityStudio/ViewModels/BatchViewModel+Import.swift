import AppKit
import Foundation
import UniformTypeIdentifiers

extension BatchViewModel {
    func choosePhotos() {
        let panel = NSOpenPanel()
        panel.title = "选择需要生成无障碍描述的照片"
        panel.prompt = "添加照片"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        addPhotos(panel.urls)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择包含照片的文件夹"
        panel.prompt = "扫描文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let root = panel.url else { return }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles, .skipsPackageDescendants
        ]
        let enumerator = FileManager.default.enumerator(at: root,
                                                        includingPropertiesForKeys: keys,
                                                        options: options)
        let urls = (enumerator?.allObjects as? [URL] ?? []).filter { url in
            let ext = url.pathExtension.lowercased()
            let isRecognizedImage = AppConfiguration.supportedExtensions.contains(ext)
                || UTType(filenameExtension: ext)?.conforms(to: .image) == true
            guard isRecognizedImage,
                  let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
        addPhotos(urls)
    }

    func addPhotos(_ urls: [URL]) {
        if !isProcessing { recognitionProgress = nil }
        let existing = Set(jobs.map { $0.url.standardizedFileURL })
        let unique = urls.filter {
            !existing.contains($0.standardizedFileURL)
        }
        var supported: [URL] = []
        var additions: [PhotoJob] = []
        for url in unique {
            let ext = url.pathExtension.lowercased()
            if AppConfiguration.supportedExtensions.contains(ext) {
                supported.append(url)
                additions.append(PhotoJob(url: url))
            } else if UTType(filenameExtension: ext)?.conforms(to: .image) == true {
                var job = PhotoJob(url: url)
                job.status = .failed
                job.errorMessage = "已保留这张素材，但当前还不能写入 .\(ext.isEmpty ? "未知" : ext) 格式的 Apple 图像描述。请转换格式后重试；原文件未修改。"
                additions.append(job)
            }
        }
        jobs.append(contentsOf: additions)
        if selectionID == nil { selectionID = jobs.first?.id }
        let unsupportedCount = additions.count - supported.count
        statusMessage = unsupportedCount == 0
            ? "已添加 \(supported.count) 张照片，共 \(jobs.count) 张。"
            : "已添加 \(additions.count) 张照片，其中 \(unsupportedCount) 张格式暂不能写入；软件没有静默丢弃。"
        announce(statusMessage)
        readExistingMetadata(for: supported)
    }

    private func readExistingMetadata(for urls: [URL]) {
        Task {
            let reader = PhotoMetadataReader()
            let metadata = (try? await Task.detached(priority: .utility) {
                try reader.read(urls)
            }.value) ?? [:]
            for url in urls {
                if let id = jobs.first(where: {
                    $0.url.standardizedFileURL == url.standardizedFileURL
                })?.id, let value = metadata[url.standardizedFileURL] {
                    update(id: id) {
                        $0.existingDescription = value.existingDescription
                        $0.captureDate = value.captureDate
                        $0.sourceFormat = value.format
                        $0.pixelWidth = value.pixelWidth
                        $0.pixelHeight = value.pixelHeight
                    }
                }
            }
        }
    }

    func auditPersistedVerifications() {
        let stored = jobs.filter {
            $0.status == .completed || $0.status == .exported
        }
        guard !stored.isEmpty else { return }
        Task {
            for job in stored {
                guard !job.description.isEmpty else {
                    update(id: job.id) {
                        $0.status = .failed
                        $0.exportedURL = nil
                        $0.errorMessage = "历史完成记录没有描述内容，已取消完成状态。"
                    }
                    continue
                }
                let target = job.status == .exported ? job.exportedURL : job.url
                guard let target,
                      FileManager.default.fileExists(atPath: target.path) else {
                    update(id: job.id) {
                        $0.status = .ready
                        $0.exportedURL = nil
                        $0.errorMessage = "历史完成记录找不到对应文件，请重新导出或写入。"
                    }
                    continue
                }
                do {
                    let writer = metadataWriter
                    _ = try await Task.detached {
                        try writer.verify(job.description, at: target)
                    }.value
                    update(id: job.id) {
                        $0.errorMessage = nil
                        if job.status == .completed {
                            $0.existingDescription = job.description
                        }
                    }
                } catch {
                    update(id: job.id) {
                        $0.status = .ready
                        $0.exportedURL = nil
                        $0.errorMessage = "历史写入记录未通过底层复核：\(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
