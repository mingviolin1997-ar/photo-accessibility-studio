import Foundation

struct RuntimeProgress: Equatable {
    let step: String
    let downloaded: Int64
    let total: Int64
    let bytesPerSecond: Double
    var detailOverride: String? = nil

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, Double(downloaded) / Double(total)))
    }

    var detail: String {
        if let detailOverride { return detailOverride }
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
    case unsupportedPlatform(String)

    var errorDescription: String? {
        switch self {
        case let .downloadFailed(value): return "下载失败：\(value)"
        case let .checksumMismatch(value): return "下载文件校验失败：\(value)"
        case let .archiveInvalid(value): return "自动安装包无效：\(value)"
        case .serverUnavailable: return "本地推理服务无法启动"
        case let .modelPullFailed(value): return "模型下载失败：\(value)"
        case let .verificationFailed(value): return "环境验证失败：\(value)"
        case let .unsupportedPlatform(value): return "当前设备不支持：\(value)"
        }
    }
}

enum RuntimeDownloadDiagnostics {
    static func message(for error: Error) -> String {
        if error is CancellationError { return "下载已取消，现有进度已保留" }
        if let setup = error as? RuntimeSetupError {
            switch setup {
            case let .downloadFailed(reason), let .modelPullFailed(reason):
                return reason
            default:
                return setup.localizedDescription
            }
        }
        let value = error.localizedDescription
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return "下载服务器长时间没有返回数据，连接超时"
            case NSURLErrorNotConnectedToInternet:
                return "当前没有可用网络连接"
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return "无法解析下载服务器地址；请检查 DNS、网络或代理"
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
                return "无法连接下载服务器或连接已中断；请检查网络、代理或防火墙"
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot:
                return "与下载服务器建立安全连接失败；请检查系统时间、网络或代理证书"
            default:
                break
            }
        }
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return "磁盘空间不足；请释放空间后重试，已下载部分仍会保留"
        }
        return value.isEmpty ? String(describing: type(of: error)) : value
    }
}
