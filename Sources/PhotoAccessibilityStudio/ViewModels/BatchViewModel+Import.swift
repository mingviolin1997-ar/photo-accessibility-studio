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
            guard AppConfiguration.supportedExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
        addPhotos(urls)
    }

    func addPhotos(_ urls: [URL]) {
        let existing = Set(jobs.map { $0.url.standardizedFileURL })
        let valid = urls.filter {
            AppConfiguration.supportedExtensions.contains($0.pathExtension.lowercased()) &&
            !existing.contains($0.standardizedFileURL)
        }
        jobs.append(contentsOf: valid.map(PhotoJob.init))
        if selectionID == nil { selectionID = jobs.first?.id }
        statusMessage = "已添加 \(valid.count) 张照片，共 \(jobs.count) 张。"
        announce(statusMessage)
        readExistingMetadata(for: valid)
    }

    private func readExistingMetadata(for urls: [URL]) {
        Task {
            for url in urls {
                let writer = metadataWriter
                let value = try? await Task.detached {
                    try writer.readDescription(from: url)
                }.value
                if let id = jobs.first(where: {
                    $0.url.standardizedFileURL == url.standardizedFileURL
                })?.id {
                    update(id: id) { $0.existingDescription = value }
                }
            }
        }
    }
}
