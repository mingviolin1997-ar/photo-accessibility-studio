import Foundation

struct ExportedPhoto {
    let sourceURL: URL
    let outputURL: URL
    let metadataResult: MetadataWriteResult
}

enum BatchExportError: LocalizedError {
    case invalidDestination
    case destinationNotWritable

    var errorDescription: String? {
        switch self {
        case .invalidDestination: return "请选择一个有效的导出文件夹"
        case .destinationNotWritable: return "所选导出文件夹不可写"
        }
    }
}

struct BatchExportService {
    let metadataWriter: MetadataWriter
    let fileManager: FileManager

    init(metadataWriter: MetadataWriter = .init(),
         fileManager: FileManager = .default) {
        self.metadataWriter = metadataWriter
        self.fileManager = fileManager
    }

    func export(description: String,
                from sourceURL: URL,
                to destinationFolder: URL) throws -> ExportedPhoto {
        let folderValues = try destinationFolder.resourceValues(
            forKeys: [.isDirectoryKey, .isWritableKey]
        )
        guard folderValues.isDirectory == true else {
            throw BatchExportError.invalidDestination
        }
        guard folderValues.isWritable == true else {
            throw BatchExportError.destinationNotWritable
        }

        let outputURL = uniqueOutputURL(for: sourceURL, in: destinationFolder)
        try fileManager.copyItem(at: sourceURL, to: outputURL)
        do {
            let result = try metadataWriter.write(description, to: outputURL)
            return ExportedPhoto(sourceURL: sourceURL,
                                 outputURL: outputURL,
                                 metadataResult: result)
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw error
        }
    }

    private func uniqueOutputURL(for sourceURL: URL,
                                 in destinationFolder: URL) -> URL {
        let original = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
        if !fileManager.fileExists(atPath: original.path),
           original.standardizedFileURL != sourceURL.standardizedFileURL {
            return original
        }

        let base = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        for number in 1...10_000 {
            let suffix = number == 1 ? "（无障碍描述）" : "（无障碍描述 \(number)）"
            let name = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            let candidate = destinationFolder.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path),
               candidate.standardizedFileURL != sourceURL.standardizedFileURL {
                return candidate
            }
        }
        return destinationFolder.appendingPathComponent("\(UUID().uuidString)-\(sourceURL.lastPathComponent)")
    }
}
