import Foundation
import Darwin

struct MetadataWriteResult {
    let verifiedDescription: String
    let integrity: ImageIntegritySnapshot
    let rawPacketVerified: Bool
}

enum MetadataWriterError: LocalizedError {
    case exifToolMissing
    case emptyDescription
    case unsupportedFormat(String)
    case commandFailed(String)
    case verificationFailed
    case integrityChanged
    case recoveryFailed(String)
    case unsafeFile(String)
    case invalidDescription

    var errorDescription: String? {
        switch self {
        case .exifToolMissing: return "未找到 ExifTool，请先安装 exiftool"
        case .emptyDescription: return "描述不能为空"
        case let .unsupportedFormat(value): return "暂不支持 \(value) 格式"
        case let .commandFailed(value): return "元数据写入失败：\(value)"
        case .verificationFailed: return "写入后读回的描述不一致"
        case .integrityChanged: return "写入导致文件名、尺寸或像素发生变化，已尝试恢复原图"
        case let .recoveryFailed(path): return "恢复原图失败；安全副本保留在 \(path)"
        case let .unsafeFile(reason): return "为保护原图，已跳过：\(reason)"
        case .invalidDescription: return "描述含有无法写入 XMP 的控制字符"
        }
    }
}

struct MetadataWriter {
    let runner = ProcessRunner()
    let integrity = ImageIntegrity()
    let packetBuilder = XMPPacketBuilder()

    func readDescription(from url: URL) throws -> String? {
        let output = try runner.run(executable: try exifToolURL(), arguments: [
            "-config", "", "-charset", "filename=UTF8",
            "-s3", "-XMP-iptcExt:ArtworkContentDescription", "--", url.path
        ])
        guard output.status == 0 else {
            throw MetadataWriterError.commandFailed(clean(output.standardError))
        }
        let value = clean(output.standardOutput)
        return value.isEmpty ? nil : value
    }

    func write(_ description: String, to url: URL) throws -> MetadataWriteResult {
        let value = try normalized(description)
        guard !value.isEmpty else { throw MetadataWriterError.emptyDescription }
        let ext = url.pathExtension.lowercased()
        guard AppConfiguration.supportedExtensions.contains(ext) else {
            throw MetadataWriterError.unsupportedFormat(ext)
        }
        try validateSafety(of: url)
        let before = try integrity.snapshot(of: url)
        let token = UUID().uuidString
        let stage = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent).pas-stage-\(token).\(ext)")
        let backupName = ".\(url.lastPathComponent).pas-backup-\(token)"
        let backup = url.deletingLastPathComponent().appendingPathComponent(backupName)
        try FileManager.default.copyItem(at: url, to: stage)
        try FileManager.default.copyItem(at: url, to: backup)
        var replacedOriginal = false

        do {
            let existingXMP = try rawXMP(from: stage)
            let packet = try packetBuilder.build(existing: existingXMP.isEmpty ? nil : existingXMP,
                                                  description: value)
            let packetURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("pas-xmp-\(token).xmp")
            try packet.write(to: packetURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: packetURL) }
            let output = try runner.run(executable: try exifToolURL(), arguments: [
                "-config", "", "-overwrite_original",
                "-charset", "filename=UTF8",
                "-XMP<=\(packetURL.path)",
                "--", stage.path
            ])
            guard output.status == 0,
                  !output.standardError.localizedCaseInsensitiveContains("warning"),
                  !output.standardError.localizedCaseInsensitiveContains("error") else {
                throw MetadataWriterError.commandFailed(clean(output.standardError + output.standardOutput))
            }
            let stagedDescription = try readDescription(from: stage)
            guard stagedDescription == value else {
                throw MetadataWriterError.commandFailed("暂存文件字段读回不一致")
            }
            try packetBuilder.validateRaw(rawXMP(from: stage))
            let staged = try integrity.snapshot(of: stage)
            guard before.pixelWidth == staged.pixelWidth,
                  before.pixelHeight == staged.pixelHeight,
                  before.pixelDigest == staged.pixelDigest else {
                throw MetadataWriterError.integrityChanged
            }
            guard Darwin.rename(stage.path, url.path) == 0 else {
                throw MetadataWriterError.commandFailed(String(cString: strerror(errno)))
            }
            replacedOriginal = true
            let finalDescription = try readDescription(from: url)
            guard finalDescription == value else {
                throw MetadataWriterError.commandFailed("最终文件字段读回不一致")
            }
            try packetBuilder.validateRaw(rawXMP(from: url))
            let after = try integrity.snapshot(of: url)
            guard before == after else { throw MetadataWriterError.integrityChanged }
            try? FileManager.default.removeItem(at: backup)
            return MetadataWriteResult(verifiedDescription: value,
                                       integrity: after,
                                       rawPacketVerified: true)
        } catch {
            try? FileManager.default.removeItem(at: stage)
            if replacedOriginal && FileManager.default.fileExists(atPath: backup.path) {
                do {
                    guard Darwin.rename(backup.path, url.path) == 0 else {
                        throw MetadataWriterError.commandFailed(String(cString: strerror(errno)))
                    }
                } catch {
                    throw MetadataWriterError.recoveryFailed(backup.path)
                }
            } else {
                try? FileManager.default.removeItem(at: backup)
            }
            throw error
        }
    }

    private func exifToolURL() throws -> URL {
        for path in ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"]
            where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw MetadataWriterError.exifToolMissing
    }

    func rawXMP(from url: URL) throws -> Data {
        let output = try runner.run(executable: try exifToolURL(), arguments: [
            "-config", "", "-b", "-XMP", "--", url.path
        ])
        guard output.status == 0 else {
            throw MetadataWriterError.commandFailed(clean(output.standardError))
        }
        return Data(output.standardOutput.utf8)
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalized(_ value: String) throws -> String {
        let scalars = value.unicodeScalars
        guard !scalars.contains(where: { $0.value == 0 || ($0.value < 32 && !CharacterSet.whitespacesAndNewlines.contains($0)) }) else {
            throw MetadataWriterError.invalidDescription
        }
        return value.precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func validateSafety(of url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isWritableKey])
        guard values.isRegularFile == true else { throw MetadataWriterError.unsafeFile("不是普通文件") }
        guard values.isSymbolicLink != true else { throw MetadataWriterError.unsafeFile("符号链接") }
        guard values.isWritable == true else { throw MetadataWriterError.unsafeFile("文件不可写") }
        guard !url.pathComponents.contains(where: { $0.lowercased().hasSuffix(".photoslibrary") }) else {
            throw MetadataWriterError.unsafeFile("不能直接修改 Photos 图库内部文件")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let links = attributes[.referenceCount] as? NSNumber, links.intValue > 1 {
            throw MetadataWriterError.unsafeFile("文件具有多个硬链接")
        }
    }
}
