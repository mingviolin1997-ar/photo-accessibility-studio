import Foundation

struct RuntimeProgress: Equatable {
    let step: String
    let downloaded: Int64
    let total: Int64
    let bytesPerSecond: Double

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, Double(downloaded) / Double(total)))
    }

    var detail: String {
        var value = "\(Self.bytes(downloaded))"
        if total > 0 { value += " / \(Self.bytes(total))" }
        if bytesPerSecond > 0 { value += "，\(Self.bytes(Int64(bytesPerSecond)))/秒" }
        return value
    }

    static func bytes(_ value: Int64) -> String {
        let count = ByteCountFormatter()
        count.countStyle = .file
        count.allowedUnits = [.useKB, .useMB, .useGB]
        count.includesUnit = true
        count.isAdaptive = true
        return count.string(fromByteCount: max(0, value))
    }
}

enum RuntimeSetupError: LocalizedError {
    case downloadFailed(String)
    case checksumMismatch(String)
    case archiveInvalid(String)
    case serverUnavailable
    case modelPullFailed(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .downloadFailed(value): return "下载失败：\(value)"
        case let .checksumMismatch(value): return "下载文件校验失败：\(value)"
        case let .archiveInvalid(value): return "自动安装包无效：\(value)"
        case .serverUnavailable: return "Ollama 本地服务无法启动"
        case let .modelPullFailed(value): return "Qwen 模型下载失败：\(value)"
        case let .verificationFailed(value): return "环境验证失败：\(value)"
        }
    }
}
