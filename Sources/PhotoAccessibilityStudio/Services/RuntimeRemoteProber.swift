import Foundation

struct RuntimeRemoteProbe: Equatable {
    let statusCode: Int
    let finalURL: URL
    let totalBytes: Int64?
    let supportsRanges: Bool

    var finalHost: String { finalURL.host ?? "未知服务器" }
}

struct RuntimeRemoteProber {
    func probe(_ source: URL) async throws -> RuntimeRemoteProbe {
        var request = URLRequest(url: source)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("PhotoAccessibilityStudio-macOS/0.8", forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (_, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RuntimeSetupError.downloadFailed("下载服务器返回了无法识别的响应")
        }
        guard http.url?.scheme?.lowercased() == "https" else {
            throw RuntimeSetupError.downloadFailed("下载服务器重定向到了非 HTTPS 地址，已为安全起见停止")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw RuntimeSetupError.downloadFailed(
                "下载服务器拒绝访问；请确认模型许可、账号权限或 Hugging Face 登录状态"
            )
        }
        guard http.statusCode == 200 || http.statusCode == 206 else {
            throw RuntimeSetupError.downloadFailed("下载服务器返回 HTTP \(http.statusCode)")
        }

        let contentRange = http.value(forHTTPHeaderField: "Content-Range")
        let total = Self.totalBytes(statusCode: http.statusCode,
                                    contentRange: contentRange,
                                    contentLength: http.value(forHTTPHeaderField: "Content-Length"))
        let acceptsRanges = http.value(forHTTPHeaderField: "Accept-Ranges")?
            .localizedCaseInsensitiveContains("bytes") == true
        return RuntimeRemoteProbe(statusCode: http.statusCode,
                                  finalURL: http.url ?? source,
                                  totalBytes: total,
                                  supportsRanges: http.statusCode == 206 || acceptsRanges)
    }

    static func totalBytes(statusCode: Int,
                           contentRange: String?,
                           contentLength: String?) -> Int64? {
        if statusCode == 206,
           let suffix = contentRange?.split(separator: "/").last,
           suffix != "*",
           let value = Int64(suffix.trimmingCharacters(in: .whitespaces)) {
            return value
        }
        guard statusCode == 200, let contentLength,
              let value = Int64(contentLength.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return value
    }
}
